defmodule Riemannx.Connections.Combined do
  @moduledoc """
  The combined connection worker works out when it's possible to use UDP and 
  will transmit via TCP when the message size exceeds the total max byte size.
  
  This ensures you get the non-blocking behaviour of UDP without dropping
  events if they exceed the byte size configured on the Riemann server. This
  connection is the recommended default.
  
  ## Configuration
  
  In order to use the combined connection module effectively the most important
  setting is the :max_udp_size. You can check your Riemann server for the
  correct value but the default is 16384.
  
  You must also ensure you have a :tcp_port and :udp_port configured. In most
  cases these are the same value but not in all. An example config is below:
  
  ```
  config :riemannx, [
    host: "localhost",
    tcp_port: 5552,
    udp_port: 8792,
    max_udp_size: 167353
  ]
  ```
  """
  alias Riemannx.Proto.Msg
  use GenServer
  
  # ===========================================================================
  # Struct
  # ===========================================================================
  defstruct [
    host: "localhost",
    tcp_port: 5555,
    udp_port: 5555,
    max_udp_size: 16384,
    tcp_socket: nil,
    udp_socket: nil
  ] 
  
  # ===========================================================================
  # Types
  # ===========================================================================
  @type t :: %Riemannx.Connections.Combined{
    host: binary(),
    tcp_port: integer(),
    udp_port: integer(),
    max_udp_size: integer(),
    tcp_socket: :gen_tcp.socket() | nil,
    udp_socket: :gen_udp.socket() | nil
  }
  
  # ===========================================================================
  # Private
  # ===========================================================================
  defp try_tcp_connect(state) do
    {:ok, tcp_socket} = 
      :gen_tcp.connect(state.host, 
                       state.tcp_port, 
                       [:binary, nodelay: true, packet: 4, active: true, reuseaddr: true])
    tcp_socket
  catch
    _ -> try_tcp_connect(state)
  end

  defp try_udp_connect do
    {:ok, udp_socket} = :gen_udp.open(0, [:binary])
    udp_socket
  catch
    _ -> try_udp_connect()
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================
  @spec start_link(Keyword.t()) :: {:ok, pid()}
  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end
  
  @spec init(Keyword.t()) :: {:ok, t()}
  def init(args) do
    Process.flag(:trap_exit, true)
    GenServer.cast(self(), {:init, args})
    {:ok, %Riemannx.Connections.Combined{}}
  end
  
  def handle_call({:max_udp_size, value}, _from, state) when is_integer(value) do 
    {:reply, value, %{state | max_udp_size: value}}
  end

  def handle_cast({:init, args}, _state) do
    state = %Riemannx.Connections.Combined{
      host: args[:host] |> to_charlist,
      tcp_port: args[:tcp_port],
      udp_port: args[:udp_port],
      max_udp_size: args[:max_udp_size]
    }
    
    tcp_socket = try_tcp_connect(state)
    udp_socket = try_udp_connect()

    {:noreply, %{state | tcp_socket: tcp_socket, udp_socket: udp_socket}}
  end
  def handle_cast({:send_msg, msg}, state) do
    msg = Riemannx.create_events_msg(msg)
    encoded = Msg.encode(msg)
    if byte_size(encoded) > state.max_udp_size do
      :gen_tcp.send(state.tcp_socket, encoded)
    else
      :gen_udp.send(state.udp_socket, state.host, state.udp_port, encoded)
    end
    :poolboy.checkin(:riemannx_pool, self())
    {:noreply, state}
  end

  def handle_info({:tcp_closed, _socket}, state) do 
    {:stop, :tcp_closed, %{state | tcp_socket: nil, udp_socket: nil}}
  end
  def handle_info({:tcp, _socket, _msg}, state), do: {:noreply, state}
  
  def terminate(_reason, state) do
    if state.udp_socket, do: :gen_udp.close(state.udp_socket)
    if state.tcp_socket, do: :gen_tcp.close(state.tcp_socket)
    :ok
  end
end
defmodule Riemannx.Connections.UDP do
  @moduledoc """
  Using the UDP connection is not recommended at all, events will be dropped if
  they exceed the max_udp_size set. You can increase this server side and set
  the desired value in this client.
  
  ## Configuration
  
  In order to use the UDP connection all you need to set is the :udp_port
  the server is listening on and the :host name of the server. You will
  also need to set the :max_udp_size setting and it should match the value
  set on the server.
  
  As the UDP only connection is not default you should also specify this as the
  worker module:
  
  ```
  config :riemannx, [
    host: "localhost",
    udp_port: 5555,
    max_udp_size: 197163,
    worker_module: Riemannx.Connections.UDP
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
    udp_port: 5555,
    max_udp_size: 16384,
    udp_socket: nil
  ]
  
  # ===========================================================================
  # Types
  # ===========================================================================
  @type t :: %Riemannx.Connections.UDP{
    host: binary(),
    udp_port: integer(),
    max_udp_size: integer(),
    udp_socket: :gen_udp.socket() | nil
  }
  
  
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
    {:ok, %Riemannx.Connections.UDP{}}
  end
  
  def handle_call({:max_udp_size, value}, _from, state) when is_integer(value) do 
    {:reply, value, %{state | max_udp_size: value}}
  end

  def handle_cast({:init, args}, _state) do
    state = %Riemannx.Connections.UDP{
      host: args[:host] |> to_charlist,
      udp_port: args[:udp_port],
      max_udp_size: args[:max_udp_size]
    }
    {:ok, udp_socket} = :gen_udp.open(0, [:binary])
    {:noreply, %{state | udp_socket: udp_socket}}
  end
  def handle_cast({:send_msg, msg}, state) do
    msg = Riemannx.create_events_msg(msg)
    encoded = Msg.encode(msg)
    unless byte_size(encoded) > state.max_udp_size do
      :ok = :gen_udp.send(state.udp_socket, state.host, state.udp_port, encoded)
    end
    :poolboy.checkin(:riemannx_pool, self())
    {:noreply, state}
  end
  
  def terminate(_reason, state) do
    if state.udp_socket, do: :gen_udp.close(state.udp_socket)
    :ok
  end
end
defmodule Riemannx.Connections.TCP do
  @moduledoc """
  Using the TCP connection will only send traffic via TCP, all traffic can be
  sent via TCP as opposed to UDP where you are limit by packet size, there is
  however an overhead penalty using purely TCP which is why the combined
  connection is the recommended default.

  ## Configuration

  In order to use the TCP connection all you need to set is the :tcp_port
  the server is listening on and the :host name of the server.

  As the TCP only connection is not default you should also specify this as the
  worker module:

  ```
  config :riemannx, [
    host: "localhost",
    tcp_port: 5552,
    worker_module: Riemannx.Connections.TCP
  ]
  ```
  """
  alias Riemannx.Proto.Msg
  require Logger
  use GenServer

  # ===========================================================================
  # Struct
  # ===========================================================================
  defstruct [
    host: "localhost",
    tcp_port: 5555,
    tcp_socket: nil,
  ]

  # ===========================================================================
  # Types
  # ===========================================================================
  @type t :: %Riemannx.Connections.TCP{
    host: binary(),
    tcp_port: integer(),
    tcp_socket: :gen_tcp.socket() | nil
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
  rescue
    e in MatchError ->
      Logger.error("[#{__MODULE__}] Unable to connect: #{inspect e}")
      try_tcp_connect(state)
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
    {:ok, %Riemannx.Connections.TCP{}}
  end

  def handle_cast({:init, args}, _state) do
    state = %Riemannx.Connections.TCP{
      host: args[:host] |> to_charlist,
      tcp_port: args[:tcp_port]
    }

    tcp_socket = try_tcp_connect(state)

    {:noreply, %{state | tcp_socket: tcp_socket}}
  end
  def handle_cast({:send_msg, msg}, state) do
    encoded = Msg.encode(msg)
    :ok = :gen_tcp.send(state.tcp_socket, encoded)
    :poolboy.checkin(:riemannx_pool, self())
    {:noreply, state}
  end


  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, :tcp_closed, %{state | tcp_socket: nil}}
  end
  def handle_info({:tcp, _socket, _msg}, state), do: {:noreply, state}

  def terminate(_reason, state) do
    if state.tcp_socket, do: :gen_tcp.close(state.tcp_socket)
    :ok
  end
end
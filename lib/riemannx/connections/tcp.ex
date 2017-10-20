defmodule Riemannx.Connections.TCP do
  @moduledoc """
  Using the TCP connection will only send traffic via TCP, all traffic can be
  sent via TCP as opposed to UDP where you are limited by packet size, there is
  however an overhead penalty using purely TCP which is why the combined
  connection is the recommended default.
  """
  @behaviour Riemannx.Connection
  alias Riemannx.Connection
  import Riemannx.Settings
  require Logger
  use GenServer

  # ===========================================================================
  # API
  # ===========================================================================
  def get_worker(_e, p), do: :poolboy.checkout(p, false, :infinity)
  def send(w, e), do: GenServer.call(w, {:send_msg, e})
  def send_async(w, e), do: GenServer.cast(w, {:send_msg, e})
  def release(w, _e, p), do: :poolboy.checkin(p, w)

  # ===========================================================================
  # Private
  # ===========================================================================
  defp try_tcp_connect(_state, 0), do: raise "Unable to connect!"
  defp try_tcp_connect(state, n) do
    {:ok, tcp_socket} =
      :gen_tcp.connect(state.host,
                       state.tcp_port,
                       [:binary, nodelay: true, packet: 4, active: true, reuseaddr: true])
    tcp_socket
  rescue
    e in MatchError ->
      Logger.error("[#{__MODULE__}] Unable to connect: #{inspect e}")
      :timer.sleep(retry_interval())
      try_tcp_connect(state, n-1)
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================
  @spec start_link(Connection.t()) :: {:ok, pid()}
  def start_link(conn), do: GenServer.start_link(__MODULE__, conn)

  @spec init(Connection.t()) :: {:ok, Connection.t()}
  def init(conn) do
    Process.flag(:trap_exit, true)
    GenServer.cast(self(), :init)
    {:ok, conn}
  end

  def handle_cast(:init, state) do
    host        = state.host |> to_charlist()
    retry_count = retry_count()
    state       = %{state | host: host}
    tcp_socket  = try_tcp_connect(state, retry_count)
    {:noreply, %{state | socket: tcp_socket}}
  end
  def handle_cast({:send_msg, msg}, state) do
    :ok = :gen_tcp.send(state.socket, msg)
    Connection.release(self(), msg)
    {:noreply, state}
  end

  def handle_call({:send_msg, msg}, _from, state) do
    reply = case :gen_tcp.send(state.socket, msg) do
      :ok ->
        :ok
      {:error, code} ->
        [error: "#{__MODULE__} | Unable to send event: #{code}", message: msg]
    end
    Connection.release(self(), msg)
    {:reply, reply, state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, :tcp_closed, %{state | socket: nil}}
  end
  def handle_info({:tcp, _socket, _msg}, state), do: {:noreply, state}

  def terminate(_reason, state) do
    if state.socket, do: :gen_tcp.close(state.socket)
    :ok
  end
end
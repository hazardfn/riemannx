defmodule Riemannx.Connections.TLS do
  @moduledoc """
  TLS is a secure TCP connection, you can use this if communicating with your
  riemann server securely is important - it carries some overhead and is much
  slower than UDP/combined but the trade-off is obviously worth it if security
  is a concern.

  ## Special Notes

  * This library was built for my use-case which required speed at the expense
  of reliability hence why combined is the default. If, however you require
  guarantees on message order then TCP / TLS is the way to go.
  """
  @behaviour Riemannx.Connection
  alias Riemannx.Connection
  alias Riemannx.Proto.Msg
  import Riemannx.Settings
  require Logger
  use GenServer

  # ===========================================================================
  # Attributes
  # ===========================================================================
  @ok Connection.query_ok()
  @no Connection.query_failed()

  # ===========================================================================
  # API
  # ===========================================================================
  def get_worker(_e, p), do: :poolboy.checkout(p, true, :infinity)
  def send(w, e), do: GenServer.call(w, {:send_msg, e})
  def send_async(w, e), do: GenServer.cast(w, {:send_msg, e})
  def query(w, m, t), do: GenServer.call(w, {:send_msg, m, t})
  def release(w, _e, p), do: :poolboy.checkin(p, w)

  # ===========================================================================
  # Private
  # ===========================================================================
  defp try_ssl_connect(_state, 0), do: raise "Unable to connect!"
  defp try_ssl_connect(state, n) do
    opts = [:binary, nodelay: true, packet: 4, active: true, reuseaddr: true]
    {:ok, ssl_socket} =
      :ssl.connect(state.host, state.tcp_port, state.ssl_opts ++ opts)
    ssl_socket
  rescue
    e in MatchError ->
      Logger.error("[#{__MODULE__}] Unable to connect: #{inspect e}")
      :timer.sleep(retry_interval())
      try_ssl_connect(state, n - 1)
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================
  @spec start_link(Connection.t()) :: {:ok, pid()}
  def start_link(conn), do: GenServer.start_link(__MODULE__, conn)

  @spec init(Connection.t()) :: {:ok, Connection.t()}
  def init(conn) do
    Process.flag(:trap_exit, true)
    Process.flag(:priority, conn.priority)
    GenServer.cast(self(), :init)
    {:ok, conn}
  end

  def handle_cast(:init, state) do
    host        = to_charlist(state.host)
    retry_count = retry_count()
    state       = %{state | host: host}
    ssl_socket  = try_ssl_connect(state, retry_count)
    {:noreply, %{state | socket: ssl_socket}}
  end
  def handle_cast({:send_msg, msg}, state) do
    :ok = :ssl.send(state.socket, msg)
    Connection.release(self(), msg)
    {:noreply, state}
  end

  def handle_call({:send_msg, msg}, _from, state) do
    reply = case :ssl.send(state.socket, msg) do
      :ok ->
        :ok
      {:error, code} ->
        [error: "#{__MODULE__} | Unable to send event: #{code}", message: msg]
    end
    Connection.release(self(), msg)
    {:reply, reply, state}
  end
  def handle_call({:send_msg, msg, to}, _from, state) do
    reply = case :ssl.send(state.socket, msg) do
      :ok ->
        :ok
      {:error, code} ->
        [error: "#{__MODULE__} | Unable to send event: #{code}", message: msg]
    end
    Connection.release(self(), msg)
    {:reply, reply, %{state | to: to}}
  end

  def handle_info({:ssl_closed, _socket}, state) do
    {:stop, :ssl_closed, %{state | socket: nil}}
  end

  def handle_info({_, _, <<@ok, r :: binary>> = m}, s) when bit_size(r) > 0 do
    Kernel.send(s.to, {:ok, Msg.decode(m)})
    {:noreply, %{s | to: nil}}
  end
  def handle_info({_, _, <<@no, r :: binary>> = m}, s) when bit_size(r) > 0 do
    Kernel.send(s.to, [error: "Query failed", message: Msg.decode(m)])
    {:noreply, %{s | to: nil}}
  end
  def handle_info({_, _, @ok}, %{to: to} = s) when is_pid(to) do
    Kernel.send(s.to, {:ok, []})
    {:noreply, %{s | to: nil}}
  end
  def handle_info({:ssl, _socket, _msg}, state), do: {:noreply, state}

  def terminate(_reason, state) do
    if state.socket, do: :ssl.close(state.socket)
    :ok
  end
end

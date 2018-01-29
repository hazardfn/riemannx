defmodule Riemannx.Connections.TCP do
  @moduledoc """
  Using the TCP connection will only send traffic via TCP, all traffic can be
  sent via TCP as opposed to UDP where you are limited by packet size, there is
  however an overhead penalty using purely TCP which is why the combined
  connection is the recommended default.

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
  def get_worker(_e), do: :poolboy.checkout(pool_name(:tcp), true, :infinity)
  def send(w, e), do: GenServer.call(w, {:send_msg, e})
  def send_async(w, e), do: GenServer.cast(w, {:send_msg, e})
  def query(w, m, t), do: GenServer.call(w, {:send_msg, m, t})
  def release(w, _e), do: :poolboy.checkin(pool_name(:tcp), w)

  # ===========================================================================
  # Private
  # ===========================================================================
  defp try_tcp_connect(_state, 0), do: raise "Unable to connect!"
  defp try_tcp_connect(state, n) do
    {:ok, tcp_socket} =
      :gen_tcp.connect(state.host,
                       state.port,
                       state.options)
    tcp_socket
  rescue
    e in MatchError ->
      Logger.error("[#{__MODULE__}] Unable to connect: #{inspect e}")
      :timer.sleep(retry_interval(:tcp))
      try_tcp_connect(state, n - 1)
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================
  @spec start_link([]) :: {:ok, pid()}
  def start_link([]), do: GenServer.start_link(__MODULE__, [])

  @spec init([]) :: {:ok, Connection.t()}
  def init([]) do
    Process.flag(:trap_exit, true)
    Process.flag(:priority, priority!(:tcp))
    GenServer.cast(self(), :init)
    {:ok, %Connection{}}
  end

  def handle_cast(:init, _state) do
    conn        = %Connection{host: to_charlist(host()),
                              port: port(:tcp),
                              options: options(:tcp)}
    retry_count = retry_count(:tcp)
    state       = conn
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
  def handle_call({:send_msg, msg, to}, _from, state) do
    reply = case :gen_tcp.send(state.socket, msg) do
      :ok ->
        :ok
      {:error, code} ->
        [error: "#{__MODULE__} | Unable to send event: #{code}", message: msg]
    end
    Connection.release(self(), msg)
    {:reply, reply, %{state | to: to}}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, :tcp_closed, %{state | socket: nil}}
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
  def handle_info({:tcp, _socket, _msg}, state), do: {:noreply, state}

  def terminate(_reason, state) do
    if state.socket, do: :gen_tcp.close(state.socket)
    :ok
  end
end

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
  alias Riemannx.Metrics
  import Kernel, except: [send: 2]
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
  def get_worker, do: :poolboy.checkout(pool_name(:tls), true, :infinity)
  def send(e, t), do: GenServer.call(get_worker(), {:send_msg, e}, t)
  def send_async(e), do: GenServer.cast(get_worker(), {:send_msg, e})
  def query(m, t), do: GenServer.call(get_worker(), {:send_msg, m, t})
  def release(w), do: :poolboy.checkin(pool_name(:tls), w)

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================
  @spec start_link([]) :: {:ok, pid()}
  def start_link([]), do: GenServer.start_link(__MODULE__, [])

  @spec init([]) :: {:ok, Connection.t()}
  def init([]) do
    Process.flag(:trap_exit, true)
    Process.flag(:priority, priority!(:tls))
    GenServer.cast(self(), :init)
    {:ok, %Connection{}}
  end

  def handle_cast(:init, _state) do
    conn = %Connection{host: to_charlist(host()), port: port(:tls), options: options(:tls)}
    retry_count = retry_count(:tls)
    state = conn
    ssl_socket = try_ssl_connect(state, retry_count)
    {:noreply, %{state | socket: ssl_socket}}
  end

  def handle_cast({:send_msg, msg}, state) do
    :ok = :ssl.send(state.socket, msg)
    Metrics.tls_message_sent(byte_size(msg))
    release(self())
    {:noreply, state}
  end

  def handle_call({:send_msg, msg}, _from, state) do
    reply =
      case :ssl.send(state.socket, msg) do
        :ok ->
          Metrics.tls_message_sent(byte_size(msg))
          release(self())
          :ok

        {:error, code} ->
          e = [error: "#{__MODULE__} | Unable to send event: #{code}", message: msg]
          Kernel.send(self(), {:error, e})
          e
      end

    {:reply, reply, state}
  end

  def handle_call({:send_msg, msg, to}, _from, state) do
    reply =
      case :ssl.send(state.socket, msg) do
        :ok ->
          Metrics.tls_message_sent(byte_size(msg))
          release(self())
          :ok

        {:error, code} ->
          e = [error: "#{__MODULE__} | Unable to send event: #{code}", message: msg]
          Kernel.send(self(), {:error, e})
          e
      end

    {:reply, reply, %{state | to: to}}
  end

  def handle_info({:error, error}, state) do
    {:stop, error, state}
  end

  def handle_info({:ssl_closed, _socket}, state) do
    {:stop, :normal, %{state | socket: nil}}
  end

  def handle_info({_, _, <<@ok, r::binary>> = m}, s) when bit_size(r) > 0 do
    Kernel.send(s.to, {:ok, Msg.decode(m)})
    {:noreply, %{s | to: nil}}
  end

  def handle_info({_, _, <<@no, r::binary>> = m}, s) when bit_size(r) > 0 do
    Kernel.send(s.to, error: "Query failed", message: Msg.decode(m))
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

  # ===========================================================================
  # Private
  # ===========================================================================
  defp try_ssl_connect(_state, 0), do: raise("Unable to connect!")

  defp try_ssl_connect(state, n) do
    {:ok, ssl_socket} = :ssl.connect(state.host, state.port, state.options)
    ssl_socket
  rescue
    e in MatchError ->
      Logger.error("[#{__MODULE__}] Unable to connect: #{inspect(e)}")
      :timer.sleep(retry_interval(:tls))
      try_ssl_connect(state, n - 1)
  end
end

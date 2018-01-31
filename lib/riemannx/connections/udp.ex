defmodule Riemannx.Connections.UDP do
  @moduledoc """
  Using the UDP connection is not recommended at all, events will be dropped if
  they exceed the max_udp_size set. You can increase this server side and set
  the desired value in this client.
  """
  @behaviour Riemannx.Connection
  alias Riemannx.Connection
  alias Riemannx.Metrics
  import Riemannx.Settings
  require Logger
  use GenServer

  # ===========================================================================
  # API
  # ===========================================================================
  def get_worker(e) do
    if byte_size(e) > max_udp_size() do
      [error: "Transmission too large!", message: e]
    else
      :poolboy.checkout(pool_name(:udp), true, :infinity)
    end
  end
  def send(w, e), do: GenServer.call(w, {:send_msg, e})
  def send_async(w, e), do: GenServer.cast(w, {:send_msg, e})
  def query(_, m, _), do: [error: "Querying via UDP is not supported", message: m]
  def release(w, _e), do: :poolboy.checkin(pool_name(:udp), w)

  # ===========================================================================
  # Private
  # ===========================================================================
  defp udp_connect(state) do
    {:ok, udp_socket} = :gen_udp.open(0, state.options)
    udp_socket
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================
  @spec start_link([]) :: {:ok, pid()}
  def start_link([]), do: GenServer.start_link(__MODULE__, [])

  @spec init([]) :: {:ok, Connection.t()}
  def init([]) do
    Process.flag(:trap_exit, true)
    Process.flag(:priority, priority!(:udp))
    GenServer.cast(self(), :init)
    {:ok, %Connection{}}
  end

  def handle_cast(:init, _state) do
    conn        = %Connection{host: to_charlist(host()),
                              port: port(:udp),
                              options: options(:udp)}
    udp_socket  = udp_connect(conn)
    {:noreply, %{conn | socket: udp_socket}}
  end
  def handle_cast({:send_msg, msg}, state) do
    :ok = :gen_udp.send(state.socket, state.host, state.port, msg)
    Metrics.udp_message_sent(byte_size(msg))
    Connection.release(self(), msg)
    {:noreply, state}
  end

  def handle_call({:send_msg, msg}, _from, state) do
    reply = case :gen_udp.send(state.socket, state.host, state.port, msg) do
      :ok ->
        Metrics.udp_message_sent(byte_size(msg))
        :ok
      {:error, code} ->
        [error: "#{__MODULE__} | Unable to send event: #{code}", message: msg]
    end
    Connection.release(self(), msg)
    {:reply, reply, state}
  end

  def terminate(_reason, state) do
    if state.socket, do: :gen_udp.close(state.socket)
    :ok
  end
end

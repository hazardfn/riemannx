defmodule Riemannx.Connections.UDP do
  @moduledoc """
  Using the UDP connection is not recommended at all, events will be dropped if
  they exceed the max_udp_size set. You can increase this server side and set
  the desired value in this client.
  """
  @behaviour Riemannx.Connection
  alias Riemannx.Connection
  alias Riemannx.Metrics
  import Kernel, except: [send: 2]
  import Riemannx.Settings
  require Logger
  use GenServer

  # ===========================================================================
  # API
  # ===========================================================================
  def checkout(t, :async) do
    :poolboy.checkout(pool_name(t), block_workers?(), checkout_timeout())
  end

  def checkout(t, :sync) do
    :poolboy.checkout(pool_name(t), true, checkout_timeout())
  end

  def send(e, t) do
    if healthy_size?(e) do
      pid = Connection.checkout(:udp, :sync)
      GenServer.call(pid, {:send_msg, e}, t)
    else
      size_error(e)
    end
  end

  def send_async(e) do
    if healthy_size?(e) do
      pid = Connection.checkout(:udp, :async)
      GenServer.cast(pid, {:send_msg, e})
    else
      size_error(e)
    end
  end

  def query(m, _), do: [error: "Querying via UDP is not supported", message: m]
  def release(w), do: :poolboy.checkin(pool_name(:udp), w)

  # ===========================================================================
  # Private
  # ===========================================================================
  defp udp_connect(state) do
    {:ok, udp_socket} = :gen_udp.open(0, state.options)
    udp_socket
  end

  defp healthy_size?(e) do
    if byte_size(e) > max_udp_size(), do: false, else: true
  end

  defp size_error(e), do: [error: "Transmission too large!", message: e]

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
    conn = %Connection{
      host: to_charlist(host()),
      port: port(:udp),
      options: options(:udp)
    }

    udp_socket = udp_connect(conn)
    {:noreply, %{conn | socket: udp_socket}}
  end

  def handle_cast({:send_msg, msg}, state) do
    :ok = :gen_udp.send(state.socket, state.host, state.port, msg)
    Metrics.udp_message_sent(byte_size(msg))
    release(self())
    {:noreply, state}
  end

  def handle_call({:send_msg, msg}, _from, state) do
    reply =
      case :gen_udp.send(state.socket, state.host, state.port, msg) do
        :ok ->
          Metrics.udp_message_sent(byte_size(msg))
          release(self())
          :ok

        {:error, code} ->
          e = [
            error: "#{__MODULE__} | Unable to send event: #{code}",
            message: msg
          ]

          Kernel.send(self(), {:error, e})
          e
      end

    {:reply, reply, state}
  end

  def handle_info({:error, error}, state) do
    {:stop, error, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  def terminate(_reason, state) do
    if state.socket, do: :gen_udp.close(state.socket)
    :ok
  end
end

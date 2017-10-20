defmodule Riemannx.Connections.UDP do
  @moduledoc """
  Using the UDP connection is not recommended at all, events will be dropped if
  they exceed the max_udp_size set. You can increase this server side and set
  the desired value in this client.
  """
  @behaviour Riemannx.Connection
  alias Riemannx.Connection
  import Riemannx.Settings
  require Logger
  use GenServer

  # ===========================================================================
  # API
  # ===========================================================================
  def get_worker(e, p) do
    if byte_size(e) > max_udp_size() do
      [error: "Transmission too large!", message: e]
    else
      :poolboy.checkout(p, false, :infinity)
    end
  end
  def send(w, e), do: GenServer.call(w, {:send_msg, e})
  def send_async(w, e), do: GenServer.cast(w, {:send_msg, e})
  def release(w, _e, p), do: :poolboy.checkin(p, w)

  # ===========================================================================
  # Private
  # ===========================================================================
  defp udp_connect(state) do
    {:ok, udp_socket} = :gen_udp.open(0, [:binary, {:sndbuf, state.max_udp_size}])
    udp_socket
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
    state       = %{state | host: host}
    udp_socket  = udp_connect(state)
    {:noreply, %{state | socket: udp_socket}}
  end
  def handle_cast({:send_msg, msg}, state) do
    :ok = :gen_udp.send(state.socket, state.host, state.udp_port, msg)
    Connection.release(self(), msg)
    {:noreply, state}
  end

  def handle_call({:send_msg, msg}, _from, state) do
    reply = case :gen_udp.send(state.socket, state.host, state.udp_port, msg) do
      :ok ->
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
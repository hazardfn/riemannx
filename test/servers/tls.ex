defmodule RiemannxTest.Servers.TLS do
  @moduledoc false

  alias Riemannx.Proto.Msg
  require Logger
  use GenServer

  def start(test_pid) do
    {:ok, server} = GenServer.start(__MODULE__, %{test_pid: test_pid, socket: nil})
    :ok = GenServer.call(server, :listen)
    :ok = GenServer.cast(server, :accept)
    {:ok, server}
  end

  def stop(server) do
    GenServer.call(server, :cleanup)
    GenServer.stop(server, :normal)
  end

  def init(state) do
    {:ok, state}
  end

  defp try_listen(port) do
    {:ok, _} = :ssl.listen(port,
    [:binary,
     packet: 4,
     active: true,
     reuseaddr: true,
     cacertfile: "test/certs/testca/cacert.pem",
     certfile: "test/certs/server/cert.pem",
     keyfile: "test/certs/server/key.pem"])
  rescue
    e in MatchError ->
      Logger.error("Failed to listen #{inspect e}")
      try_listen(port)
  end
  def handle_call(:listen, _from, state) do
    port = Application.get_env(:riemannx, :tcp_port, 5555)
    {:ok, socket} = try_listen(port)
    {:reply, :ok, %{state | socket: socket}}
  end
  def handle_call(:cleanup, _from, state) do
    if state.socket, do: :ssl.close(state.socket)
    {:reply, :ok, %{state | socket: nil}}
  end

  def handle_cast(:accept, %{test_pid: _pid, socket: socket} = state) do
    {:ok, client} = :ssl.transport_accept(socket)
    :ok = :ssl.ssl_accept(client)
    {:noreply, %{state | socket: client}}
  end

  def handle_info({:ssl, _port, msg}, state) do
    decoded = Msg.decode(msg)
    events  = Enum.map(decoded.events, fn(e) -> %{e | time: 0} end)
    decoded = %{decoded | events: events}
    msg     = Msg.encode(decoded)
    send(state.test_pid, {msg, :ssl})
    {:noreply, state}
  end
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end

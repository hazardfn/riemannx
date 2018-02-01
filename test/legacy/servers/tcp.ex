defmodule RiemannxTest.Legacy.Servers.TCP do
  @moduledoc false

  alias Riemannx.Proto.Msg
  use GenServer

  def start(test_pid) do
    state = %{test_pid: test_pid, socket: nil, response: nil}
    {:ok, server} = GenServer.start(__MODULE__, state)
    :ok = GenServer.call(server, :listen)
    :ok = GenServer.cast(server, :accept)
    {:ok, server}
  end

  def set_qr_response(s, r), do: GenServer.call(s, {:qr, r})

  def stop(server) do
    GenServer.call(server, :cleanup)
    GenServer.stop(server, :normal)
  end

  def init(state) do
    {:ok, state}
  end

  defp try_listen(port) do
    args = [:binary, packet: 4, active: true, reuseaddr: true]
    {:ok, _} = :gen_tcp.listen(port, args)
  rescue
    MatchError -> try_listen(port)
  end

  def handle_call(:listen, _from, state) do
    port = Application.get_env(:riemannx, :tcp_port, 5555)
    {:ok, socket} = try_listen(port)
    {:reply, :ok, %{state | socket: socket}}
  end

  def handle_call(:cleanup, _from, state) do
    if state.socket, do: :gen_tcp.close(state.socket)
    {:reply, :ok, %{state | socket: nil}}
  end

  def handle_call({:qr, response}, _from, state) do
    {:reply, :ok, %{state | response: response}}
  end

  def handle_cast(:accept, %{test_pid: _pid, socket: socket} = state) do
    {:ok, client} = :gen_tcp.accept(socket)
    {:noreply, %{state | socket: client}}
  end

  def handle_info({:tcp, _port, msg}, %{response: nil} = state) do
    decoded = Msg.decode(msg)
    events = Enum.map(decoded.events, fn e -> %{e | time: 0} end)
    decoded = %{decoded | events: events}
    msg = Msg.encode(decoded)
    send(state.test_pid, {msg, :tcp})
    {:noreply, state}
  end

  def handle_info({:tcp, _port, _msg}, %{response: qr} = state) do
    :gen_tcp.send(state.socket, qr)
    {:noreply, %{state | response: nil}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end

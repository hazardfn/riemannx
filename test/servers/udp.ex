defmodule RiemannxTest.Servers.UDP do
  @moduledoc false

  alias Riemannx.Proto.Msg
  use GenServer

  def start(test_pid) do
    {:ok, server} = GenServer.start(__MODULE__, %{test_pid: test_pid, socket: nil})
    :ok = GenServer.call(server, :open)
    {:ok, server}
  end

  def stop(server) do
    GenServer.call(server, :cleanup)
    GenServer.stop(server, :normal)
  end

  def init(state) do
    {:ok, state}
  end

  def try_open(port, max_size) do
    {:ok, _} = :gen_udp.open(port, [:binary, active: true, recbuf: max_size])
  rescue
    MatchError -> try_open(port, max_size)
  end
  def handle_call(:open, _from, state) do
    port     = Application.get_env(:riemannx, :udp_port, 5555)
    max_size = Application.get_env(:riemannx, :max_udp_size, 16_384)
    {:ok, socket} = try_open(port, max_size)
    {:reply, :ok, %{state | socket: socket}}
  end
  def handle_call(:cleanup, _from, state) do
    if state.socket, do: :gen_udp.close(state.socket)
    {:reply, :ok, %{state | socket: nil}}
  end

  def handle_info({:udp, _, _, _, msg}, state) do
    decoded = Msg.decode(msg)
    events  = Enum.map(decoded.events, fn(e) -> %{e | time: 0} end)
    decoded = %{decoded | events: events}
    msg     = Msg.encode(decoded)
    send(state.test_pid, {msg, :udp})
    {:noreply, state}
  end
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end

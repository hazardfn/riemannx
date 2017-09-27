defmodule RiemannxTest.Servers.TCP do
  use GenServer

  def start(test_pid) do
    {:ok, server} = GenServer.start(__MODULE__, %{test_pid: test_pid, socket: nil})
    :ok = GenServer.call(server, :listen)
    :ok = GenServer.cast(server, :accept)
    {:ok, server}
  end

  def stop(server) do
    Process.exit(server, :shutdown)
  end

  def init(state) do
    {:ok, state}
  end

  def handle_call(:listen, _from, state) do
    port = Application.get_env(:riemannx, :tcp_port, 5555)
    {:ok, socket} = :gen_tcp.listen(port, [:binary, packet: 4, active: true, reuseaddr: true])
    {:reply, :ok, %{state | socket: socket}}
  end

  def handle_cast(:accept, %{test_pid: _pid, socket: socket} = state) do
    {:ok, client} = :gen_tcp.accept(socket)
    {:noreply, %{state | socket: client}}
  end

  def handle_info({:tcp, _port, msg}, state) do
    send(state.test_pid, {msg, :tcp})
    {:noreply, state}
  end
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  def terminate(_reason, state) do
    :gen_tcp.close(state.socket)
  end
end
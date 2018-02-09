defmodule RiemannxTest.Servers.TCP do
  @moduledoc """
  A simple TCP server that forwards messages received back to the test process
  """
  alias Riemannx.Proto.Msg
  alias Riemannx.Settings
  use GenServer
  @behaviour RiemannxTest.Server

  # ===========================================================================
  # Callbacks
  # ===========================================================================
  def start(return_pid) do
    state = %{test_pid: return_pid, socket: nil, response: nil}
    {:ok, server} = GenServer.start(__MODULE__, state, name: __MODULE__)
    :ok = GenServer.call(server, :listen)
    :ok = GenServer.cast(server, :accept)
    {:ok, server}
  end

  def set_response(response), do: GenServer.call(__MODULE__, {:response, response})

  def stop do
    GenServer.call(__MODULE__, :cleanup)
    GenServer.stop(__MODULE__, :normal)
    :ok
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================
  def init(state), do: {:ok, state}

  def handle_call(:listen, _, s), do: listen(s)
  def handle_call(:cleanup, _, s), do: cleanup(s)
  def handle_call({:response, r}, _, s), do: {:reply, :ok, %{s | response: r}}

  def handle_cast(:accept, s), do: accept(s)

  def handle_info({:tcp, _port, msg}, %{response: nil} = state) do
    decoded = Msg.decode(msg)
    events = Enum.map(decoded.events, fn e -> %{e | time: 0, time_micros: 0} end)
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

  # ===========================================================================
  # Private
  # ===========================================================================
  defp cleanup(state) do
    if state.socket, do: :gen_tcp.close(state.socket)
    {:reply, :ok, %{state | socket: nil}}
  end

  defp listen(state) do
    port = Settings.port(:tcp)
    {:ok, socket} = try_listen(port)
    {:reply, :ok, %{state | socket: socket}}
  end

  defp try_listen(port) do
    args = [:binary, packet: 4, active: true, reuseaddr: true]
    {:ok, _} = :gen_tcp.listen(port, args)
  rescue
    MatchError -> try_listen(port)
  end

  defp accept(state) do
    {:ok, client} = :gen_tcp.accept(state.socket)
    {:noreply, %{state | socket: client}}
  end
end

defmodule RiemannxTest.Servers.UDP do
  @moduledoc """
  A simple UDP server that forwards messages received back to the test process
  """
  alias Riemannx.Proto.Msg
  use GenServer
  @behaviour RiemannxTest.Server
  
  # ===========================================================================
  # Callbacks
  # ===========================================================================
  def start(return_pid) do
    {:ok, server} = GenServer.start(__MODULE__, %{test_pid: return_pid, socket: nil}, [name: __MODULE__])
    :ok = GenServer.call(__MODULE__, :open)
    {:ok, server}
  end

  def set_response(response), do: GenServer.call(__MODULE__, {:response, response})

  def stop() do
    GenServer.call(__MODULE__, :cleanup)
    GenServer.stop(__MODULE__, :normal)
    :ok
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================
  def init(state), do: {:ok, state}

  def handle_call(:open, _, s), do: open(s)
  def handle_call({:response, r}, _, s), do: {:reply, :ok, %{s | response: r}}
  def handle_call(:cleanup, _, s), do: cleanup(s)

  def handle_info({:udp, _, _, _, msg}, state) do
    decoded = Msg.decode(msg)
    events  = Enum.map(decoded.events, fn(e) -> %{e | time: 0} end)
    decoded = %{decoded | events: events}
    msg     = Msg.encode(decoded)
    send(state.test_pid, {msg, :udp})
    {:noreply, state}
  end
  def handle_info(_msg, state), do: {:noreply, state}

  # ===========================================================================
  # Private
  # ===========================================================================
  defp cleanup(state) do
    if state.socket, do: :gen_udp.close(state.socket)
    {:reply, :ok, %{state | socket: nil}}
  end

  defp open(state) do
    port     = Riemannx.Settings.port(:udp)
    max_size = Riemannx.Settings.max_udp_size() 
    {:ok, socket} = try_open(port, max_size)
    {:reply, :ok, %{state | socket: socket}}
  end 
  def try_open(port, max_size) do
    {:ok, _} = :gen_udp.open(port, [:binary, active: true, recbuf: max_size])
  rescue
    MatchError -> try_open(port, max_size)
  end
end

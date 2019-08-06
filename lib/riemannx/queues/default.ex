defmodule Riemannx.Queues.Default do
  @doc """
  A queue allows you to use non-blocking workers and to retry data sends at a
  later time as workers become free. This keeps your process message queue
  free and prevents performance degradation under high load.

  The current implementation works by mimicing a connection GenServer. If,
  when a worker is requested, they are busy the pid to the queue is returned
  instead and messages are captured there and processed as the backend desires.

  The default queueing mechanism uses a simple queue in a GenServer state to
  manage messages. While this is optimal for my use-case your needs may require
  a more robust solution using external systems and added guarantees.
  """
  alias Riemannx.Proto.Msg
  import Riemannx.Settings
  use GenServer

  defstruct [
    :queue,
    {:pending_flush, false},
    {:ongoing_flush, false},
    :flush_ref
  ]

  # ===========================================================================
  # API
  # ===========================================================================
  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: queue_name())

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================
  def init(_opts) do
    Process.send_after(self(), :flush, queue_interval())
    {:ok, %__MODULE__{queue: Qex.new()}}
  end

  def handle_cast({:send_msg, event}, state) do
    event = Msg.decode(event).events
    state = %__MODULE__{queue: queue} = push(state, event)

    if queue_big_enough_to_flush?(queue),
      do: {:noreply, flush(state)},
      else: {:noreply, state}
  end

  def handle_info(:flush, state), do: {:noreply, flush(state)}

  # a previous flush is finished, check if anyone requested another one in the meantime
  def handle_info(
        {:DOWN, ref, :process, _, _},
        state = %__MODULE__{flush_ref: ref}
      ),
      do: {:noreply, state |> clear_ongoing_flush() |> flush_if_pending()}

  def handle_info(_, state), do: {:noreply, state}

  # ===========================================================================
  # Private
  # ===========================================================================
  defp flush(items, :udp) when is_list(items) do
    Enum.each(items, fn item ->
      [events: item]
      |> Msg.new()
      |> Msg.encode()
      |> module().send_async()
    end)

    Process.send_after(self(), :flush, queue_interval())
    nil
  end

  defp flush(items, _) when is_list(items) do
    batch =
      Enum.flat_map(items, fn item ->
        item
      end)

    {_, ref} =
      spawn_monitor(fn ->
        [events: batch]
        |> Msg.new()
        |> Msg.encode()
        |> module().send_async()
      end)

    Process.send_after(self(), :flush, queue_interval())
    ref
  end

  defp flush(state = %__MODULE__{ongoing_flush: true}) do
    # try again when the flush is done
    %__MODULE__{state | pending_flush: true}
  end

  defp flush(state = %__MODULE__{queue: queue}) do
    # the queue can grow larger than the configured batch size while we're waiting;
    # if the remaining part is still big enough to flush, we'll do it right after this flush proc exits
    {flush_window, remaining} = queue |> Enum.split(queue_size())
    ref = flush_window |> flush(type())
    remaining_queue = Qex.new(remaining)

    %__MODULE__{
      state
      | pending_flush: queue_big_enough_to_flush?(remaining_queue),
        ongoing_flush: true,
        flush_ref: ref,
        queue: remaining_queue
    }
  end

  defp flush_if_pending(state = %__MODULE__{pending_flush: true}),
    do: flush(state)

  defp flush_if_pending(state), do: state

  defp clear_ongoing_flush(state = %__MODULE__{}),
    do: %__MODULE__{state | ongoing_flush: false, flush_ref: nil}

  defp push(state = %__MODULE__{queue: queue}, event) do
    %__MODULE__{state | queue: Qex.push(queue, event)}
  end

  defp queue_big_enough_to_flush?(queue), do: Enum.count(queue) >= queue_size()
end

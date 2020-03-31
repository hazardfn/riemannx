defmodule Riemannx.Connections.Batch do
  @moduledoc """
  The batch connector is a pass through module that adds batching functionality
  on top of the existing protocol connections.

  Batching will aggregate events you send and then send them in bulk in
  intervals you specify, if the events reach a certain size you can set it so
  they publish the events before the interval.

  NOTE: Batching **only** works with send_async.

  Below is how the batching settings look in config:

  ```elixir
    config :riemannx, [
      type: :batch
      batch_settings: [
        type: :combined
        size: 50 # Sends when the batch size reaches 50
        interval: {5, :seconds} # How often to send the batches if they don't reach :size (:seconds, :minutes or :milliseconds)
      ]
    ]

  ## Synchronous Sending

  When you send synchronously the events are passed directly through to the underlying connection
  module. They are not batched or put in the queue.
  ```
  """

  import Riemannx.Settings
  import Kernel, except: [send: 2]
  alias Riemannx.Connections.Batch.Queue
  alias Riemannx.Proto.Msg
  alias __MODULE__
  use GenServer

  @behaviour Riemannx.Connection

  defstruct [
    :queue,
    {:pending_flush, false},
    {:ongoing_flush, false},
    :flush_ref
  ]

  # ===========================================================================
  # API
  # ===========================================================================
  def send(e, t), do: batch_module().send(e, t)
  def send_async(e), do: GenServer.cast(__MODULE__, {:push, e})
  def query(m, t), do: batch_module().query(m, t)

  # ===========================================================================
  # GenStage Callbacks
  # ===========================================================================
  def start_link([]) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_) do
    Process.send_after(self(), :flush, batch_interval())
    {:ok, %Batch{queue: Queue.new()}}
  end

  def handle_cast({:push, event}, state) do
    state = %Batch{queue: queue} = push(state, event)

    if Queue.batch_available?(queue),
      do: {:noreply, flush(state)},
      else: {:noreply, state}
  end

  def handle_info(:flush, state), do: {:noreply, flush(state)}

  # a previous flush is finished, check if anyone requested another one in the meantime
  def handle_info(
        {:DOWN, ref, :process, _, _},
        state = %Batch{flush_ref: ref}
      ),
      do: {:noreply, state |> clear_ongoing_flush() |> flush_if_pending()}

  def handle_info(_, state), do: {:noreply, state}

  # ===========================================================================
  # Private
  # ===========================================================================
  defp flush([]) do
    Process.send_after(self(), :flush, batch_interval())
    nil
  end

  defp flush(items) when is_list(items) do
    ref =
      items
      |> Enum.flat_map(fn item -> item end)
      |> do_spawn()

    Process.send_after(self(), :flush, batch_interval())
    ref
  end

  defp flush(state = %Batch{ongoing_flush: true}) do
    # try again when the flush is done
    %Batch{state | pending_flush: true}
  end

  defp flush(state = %Batch{queue: queue}) do
    # the queue can grow larger than the configured batch size while we're waiting;
    # if the remaining part is still big enough to flush, we'll do it right after
    # this flush proc exits
    {:ok, {remaining_queue, batch}} = Queue.get_batch(queue)
    ref = flush(batch)
    %Batch{
      state
      | pending_flush: Queue.batch_available?(queue),
        ongoing_flush: ref != nil,
        flush_ref: ref,
        queue: remaining_queue,
    }
  end

  defp flush_if_pending(state = %Batch{pending_flush: true}),
    do: flush(state)

  defp flush_if_pending(state), do: state

  defp clear_ongoing_flush(state = %Batch{}),
    do: %Batch{state | ongoing_flush: false, flush_ref: nil}

  defp push(state = %Batch{queue: queue}, event),
    do: %Batch{state | queue: Queue.push(queue, event)}

  defp do_spawn(batch) do
    {_, ref} =
      spawn_monitor(fn ->
        [events: batch]
        |> Msg.new()
        |> Msg.encode()
        |> batch_module().send_async()
      end)

    ref
  end

  defmodule Queue do
    @moduledoc """
    Queue implementation for the batch module

    Internally it maintains two queues:

    - buffer: Contains the latest elements being inserted before the
    size of a batch is reached
    - batches: It has the ordered list of batches ready to be sent as
    required

    The main idea is that batches are created as the queue is filled up.
    In this way, it avoids problems if the amount of events to be sent is
    too big as everything is precalculated on a smaller queue (buffer)
    """

    require Logger

    alias Riemannx.Settings
    alias __MODULE__

    defstruct [
      {:buffer, Qex.new()},
      {:buffer_size, 0},
      {:batches, Qex.new()},
      {:batch_count, 0},
      {:drop_count, 0}
    ]

    # ===========================================================================
    # API
    # ===========================================================================
    def new, do: %Queue{}

    def push(queue, event), do: push(queue, event, Settings.batch_limit())

    def get_batch(
      %{buffer: buffer, batches: batches, batch_count: count} = queue
    ) do
      case Qex.pop(batches) do
        {:empty, _} ->
          batch = Enum.to_list(buffer)
          nqueue = %{
            queue |
            buffer: Qex.new(),
            buffer_size: 0
          }
          {:ok, {nqueue, batch}}
        {{:value, batch}, nbatches} ->
          nqueue = %{
            queue |
            batches: nbatches,
            batch_count: count - 1
          }
          {:ok, {nqueue, batch}}
      end
    end

    def batch_available?(%{batch_count: count}), do: count > 0

    # ===========================================================================
    # Private
    # ===========================================================================
    defp push(%{batch_count: count, drop_count: dcount} = queue, _event, limit)
    when count >= limit,
      do: %{queue | drop_count: dcount + 1}

    defp push(%{buffer: buffer, buffer_size: size} = queue, event, _limit) do
      nqueue = %{
        queue |
        buffer: Qex.push(buffer, event),
        buffer_size: size + 1
      }

      nqueue
      |> create_batch_maybe()
      |> report_dropped_maybe()
    end

    defp create_batch_maybe(nqueue),
      do: create_batch_maybe(nqueue, Settings.batch_size())

    defp create_batch_maybe(
      %{
        buffer_size: size,
        buffer: buffer,
        batches: batches,
        batch_count: count
      } = queue,
      bsize
    ) when size >= bsize do
      %{
        queue |
        buffer: Qex.new(),
        buffer_size: 0,
        batches: Qex.push(batches, Enum.to_list(buffer)),
        batch_count: count + 1
      }
    end

    defp create_batch_maybe(queue, _bsize), do: queue

    defp report_dropped_maybe(%{drop_count: dcount} = queue) when dcount > 0 do
      Logger.warn("Riemannx: Dropped #{dcount} events due to overloading")
      %{queue | drop_count: 0}
    end

    defp report_dropped_maybe(queue), do: queue

  end

end

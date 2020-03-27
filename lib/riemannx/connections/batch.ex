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
  alias Riemannx.Connections.BatchQueue
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
    {:ok, %Batch{queue: BatchQueue.new()}}
  end

  def handle_cast({:push, event}, state) do
    state = %Batch{queue: queue} = push(state, event)

    if BatchQueue.batch_available?(queue),
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
    {:ok, {remaining_queue, batch}} = BatchQueue.get_batch(queue)
    ref = flush(batch)
    %Batch{
      state
      | pending_flush: BatchQueue.batch_available?(queue),
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
    do: %Batch{state | queue: BatchQueue.push(queue, event)}

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
end

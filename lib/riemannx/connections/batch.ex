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
  alias Riemannx.Proto.Msg
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
    {:ok, %__MODULE__{queue: Qex.new()}}
  end

  def handle_cast({:push, event}, state) do
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
  defp flush([]) do
    Process.send_after(self(), :flush, batch_interval())
    nil
  end

  defp flush(items) when is_list(items) do
    batch =
      Enum.flat_map(items, fn item ->
        item
      end)

    {_, ref} =
      spawn_monitor(fn ->
        [events: batch]
        |> Msg.new()
        |> Msg.encode()
        |> batch_module().send_async()
      end)

    Process.send_after(self(), :flush, batch_interval())
    ref
  end

  defp flush(state = %__MODULE__{ongoing_flush: true}) do
    # try again when the flush is done
    %__MODULE__{state | pending_flush: true}
  end

  defp flush(state = %__MODULE__{queue: queue}) do
    # the queue can grow larger than the configured batch size while we're waiting;
    # if the remaining part is still big enough to flush, we'll do it right after this flush proc exits
    {flush_window, remaining} = queue |> Enum.split(batch_size())
    ref = flush_window |> flush()
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

  defp queue_size(queue), do: Enum.count(queue)

  defp queue_big_enough_to_flush?(queue), do: queue_size(queue) >= batch_size()
end

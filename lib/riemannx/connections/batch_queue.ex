defmodule Riemannx.Connections.BatchQueue do
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

  alias Riemannx.Settings
  alias __MODULE__

  defstruct [
    {:buffer, Qex.new()},
    {:buffer_size, 0},
    {:batches, Qex.new()}
  ]

  # ===========================================================================
  # API
  # ===========================================================================
  def new, do: %BatchQueue{}

  def push(%{buffer: buffer, buffer_size: size} = queue, event) do
    nqueue = %{
      queue |
      buffer: Qex.push(buffer, event),
      buffer_size: size + 1
    }

    create_batch_maybe(nqueue)
  end

  def get_batch(%{buffer: buffer, batches: batches} = queue) do
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
          batches: nbatches
        }
        {:ok, {nqueue, batch}}
    end
  end

  def batch_available?(%{batches: batches}), do: not Enum.empty?(batches)

  # ===========================================================================
  # Private
  # ===========================================================================
  defp create_batch_maybe(nqueue),
    do: create_batch_maybe(nqueue, Settings.batch_size())


  defp create_batch_maybe(
    %{buffer_size: size, buffer: buffer, batches: batches} = queue,
    bsize
  ) when size >= bsize do
    %{
      queue |
      buffer: Qex.new(),
      buffer_size: 0,
      batches: Qex.push(batches, Enum.to_list(buffer))
    }
  end

  defp create_batch_maybe(queue, _bsize), do: queue

end

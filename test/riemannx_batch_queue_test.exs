defmodule RiemannxTest.BatchQueue do
  alias Riemannx.Connections.Batch.Queue
  alias Riemannx.Settings

  use ExUnit.Case, async: false

  test "Batch queue tests" do
    batch_size = Settings.batch_size()
    events1 = for i <- 1..1_000, do: i
    events2 = for i <- 1_000..2_000, do: i
    batch1 = for i <- 1..batch_size, do: i
    batch2 = for i <- batch_size+1..2*batch_size, do: i
    push_fun = fn e, q -> Queue.push(q, e) end

    ## Fresh queue
    q0 = Queue.new()
    assert false == Queue.batch_available?(q0)
    assert {:ok, {q0, []}} == Queue.get_batch(q0)

    ## Queue with events
    q1 = Enum.reduce(events1, q0, push_fun)
    assert true == Queue.batch_available?(q1)
    {:ok, {q2, batch}} = Queue.get_batch(q1)
    assert batch == batch1

    ## Add more events and test second batch
    q3 = Enum.reduce(events2, q2, push_fun)
    {:ok, {_q4, batch}} = Queue.get_batch(q3)
    assert batch == batch2
  end
end

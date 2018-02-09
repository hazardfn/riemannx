defmodule RiemannxTest.Batch do
  use ExUnit.Case, async: false
  use PropCheck
  import Riemannx.Settings
  alias Riemannx.Proto.Msg
  alias RiemannxTest.Utils
  alias RiemannxTest.Server
  alias Riemannx.Connections.Batch
  alias RiemannxTest.Property.RiemannXPropTest, as: Prop
  alias Riemannx.Proto.Event
  require IEx

  setup_all do
    Application.load(:riemannx)
    Application.put_env(:riemannx, :type, :batch)
    :ok
  end

  setup do
    Utils.update_setting(:udp, :max_size, 16_384)
    Utils.update_setting(:udp, :port, 5555)
    Utils.update_setting(:tcp, :port, 5555)
    Utils.update_batch_setting(:size, 100)
    Utils.update_batch_setting(:interval, {100, :milliseconds})
    {:ok, tcp_server} = Server.start(:tcp, self())
    {:ok, udp_server} = Server.start(:udp, self())
    Application.ensure_all_started(:riemannx)

    on_exit(fn ->
      Server.stop(:tcp)
      Server.stop(:udp)
      Application.stop(:riemannx)
    end)

    [tcp_server: tcp_server, udp_server: udp_server]
  end

  test "send_async/1 can send an event" do
    event = [
      service: "riemannx-elixir",
      metric: 1,
      attributes: [a: 1],
      description: "test"
    ]

    Riemannx.send_async(event)
    assert_events_received(event)
  end

  test "send_async/1 can send multiple events" do
    events = [
      [
        service: "riemann-elixir",
        metric: 1,
        attributes: [a: 1],
        description: "hurr durr"
      ],
      [
        service: "riemann-elixir-2",
        metric: 1.123,
        attributes: [a: 1, b: 2],
        description: "hurr durr dee durr"
      ],
      [
        service: "riemann-elixir-3",
        metric: 5.123,
        description: "hurr durr dee durr derp"
      ],
      [
        service: "riemann-elixir-4",
        state: "ok"
      ]
    ]

    Riemannx.send_async(events)
    assert_events_received(events)
  end

  test "The message is still sent given a small max_udp_size" do
    events = [
      [
        service: "riemann-elixir",
        metric: 1,
        attributes: [a: 1],
        description: "hurr durr"
      ],
      [
        service: "riemann-elixir-2",
        metric: 1.123,
        attributes: [a: 1, b: 2],
        description: "hurr durr dee durr"
      ],
      [
        service: "riemann-elixir-3",
        metric: 5.123,
        description: "hurr durr dee durr derp"
      ],
      [
        service: "riemann-elixir-4",
        state: "ok"
      ]
    ]

    Utils.update_setting(:udp, :max_size, 1)
    Riemannx.send_async(events)
    assert_events_received(events, :tcp)
  end

  test "Queries are forwarded via TCP" do
    event = [
      service: "riemannx-elixir",
      metric: 1,
      attributes: [a: 1],
      description: "test"
    ]

    event = Msg.decode(Riemannx.create_events_msg(event)).events
    msg = Msg.new(ok: true, events: event)
    msg = Msg.encode(msg)

    Server.set_response(:tcp, msg)
    events = Riemannx.query("test")
    assert events == Event.deconstruct(event)
  end

  test "Batching with a high interval won't send unless the size is exceeded" do
    event = [
      service: "riemannx-elixir",
      metric: 1,
      attributes: [a: 1],
      description: "test"
    ]

    Utils.update_batch_setting(:size, 10)
    Utils.update_batch_setting(:interval, {60, :minutes})
    GenServer.stop(Batch)
    Batch.start_link([])

    Enum.each(1..9, fn _ ->
      Riemannx.send_async(event)
    end)

    refute assert_events_received(event, 5000)
    Riemannx.send_async(event)

    Enum.each(1..10, fn _ ->
      assert assert_events_received(event)
    end)
  end

  test "Batching will still send events at the right interval even if the size is not reached" do
    event = [
      service: "riemannx-elixir",
      metric: 1,
      attributes: [a: 1],
      description: "test"
    ]

    Utils.update_batch_setting(:size, 10)
    Utils.update_batch_setting(:interval, {500, :milliseconds})
    GenServer.stop(Batch)
    Batch.start_link([])

    Enum.each(1..9, fn _ ->
      Riemannx.send_async(event)
    end)

    Enum.each(1..9, fn _ ->
      assert assert_events_received(event, 1000)
    end)
  end

  property "All reasonable metrics async", [:verbose] do
    numtests(
      100,
      forall events in Prop.encoded_events() do
        events = Prop.deconstruct_events(events)
        Riemannx.send_async(events)
        __MODULE__.assert_events_received(events) == true
      end
    )
  end

  property "All reasonable metrics sync", [:verbose] do
    numtests(
      100,
      forall events in Prop.encoded_events() do
        events = Prop.deconstruct_events(events)
        :ok = Riemannx.send(events)
        __MODULE__.assert_events_received(events) == true
      end
    )
  end

  def refute_events_received do
    receive do
      {<<>>, :udp} -> refute_events_received()
      {_, :udp} -> false
    after
      1100 -> true
    end
  end

  def assert_events_received(events, timeout \\ 10_000)

  def assert_events_received(events, timeout) when is_integer(timeout) do
    orig = Riemannx.create_events_msg(events)
    msg = Msg.decode(orig)
    events = Enum.map(msg.events, fn e -> %{e | time: 0, time_micros: 0} end)
    msg = %{msg | events: events}
    encoded = Msg.encode(msg)

    receive do
      {^encoded, x} ->
        if byte_size(orig) > max_udp_size() do
          assert x == :tcp
          true
        else
          assert x == :udp
          true
        end
    after
      timeout -> false
    end
  end

  def assert_events_received(events, x) when is_atom(x) do
    msg = events |> Riemannx.create_events_msg() |> Msg.decode()
    events = Enum.map(msg.events, fn e -> %{e | time: 0, time_micros: 0} end)
    msg = %{msg | events: events}
    encoded = Msg.encode(msg)

    receive do
      {^encoded, ^x} -> true
    after
      10_000 -> false
    end
  end
end

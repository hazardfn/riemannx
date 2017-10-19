defmodule RiemannxTest.UDP do
  use ExUnit.Case, async: false
  use PropCheck
  require IEx
  alias Riemannx.Proto.Msg
  alias RiemannxTest.Property.RiemannXPropTest, as: Prop

  setup_all do
    Application.load(:riemannx)
    Application.put_env(:riemannx, :worker_module, Riemannx.Connections.UDP)
    :ok
  end

  setup do
    {:ok, server} = RiemannxTest.Servers.UDP.start(self())
    Application.ensure_all_started(:riemannx)

    on_exit(fn() ->
      RiemannxTest.Servers.UDP.stop(server)
      Application.stop(:riemannx)
    end)

    [server: server]
  end

  test "send_async/1 can send an event" do
    event = [
      service: "riemannx-elixir",
      metric: 1,
      attributes: [a: 1],
      description: "test"
    ]
    Riemannx.send_async(event)
    assert assert_events_received(event)
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
        attributes: [a: 1, "b": 2],
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
    assert assert_events_received(events)
  end

  test "send_async/1 ignores UDP requests over the limit" do
    event = [
      service: "riemannx-elixir",
      metric: 1,
      attributes: [a: 1],
      description: "test"
    ]
    :poolboy.transaction(
      :riemannx_pool,
        fn(pid) ->
          GenServer.call(pid, {:max_udp_size, 1})
        end,
      :infinity
    )
    Riemannx.send_async(event)
    assert refute_events_received()
  end

  property "All reasonable metrics", [:verbose] do
    numtests(500, forall events in Prop.udp_events(16384) do
        events = Prop.deconstruct_events(events)
        Riemannx.send_async(events)
        (__MODULE__.assert_events_received(events) == true)
    end)
  end

  def refute_events_received() do
    receive do
      {_, :udp} -> false
    after
      500 -> true
    end
  end
  def assert_events_received(events) do
    msg     = Riemannx.create_events_msg(events)
    events  = msg.events |> Enum.map(fn(e) -> %{e | time: 0} end)
    msg     = %{msg | events: events}
    encoded = Msg.encode(msg)
    receive do
      {^encoded, :udp} -> true
    after
      500 -> false
    end
  end
end

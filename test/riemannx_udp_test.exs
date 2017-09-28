defmodule RiemannxTest.UDP do
  use ExUnit.Case, async: false
  alias Riemannx.Proto.Msg
  alias Riemannx.Proto.Event
  alias Riemannx.Errors.InvalidMetricError

  setup_all do
    Application.load(:riemannx)
    Application.put_env(:riemannx, :worker_module, Riemannx.Connections.UDP)
  end

  setup do
    {:ok, server} = RiemannxTest.Servers.UDP.start(self())
    Application.ensure_all_started(:riemannx)

    on_exit(fn() ->
      Application.stop(:riemannx)
      RiemannxTest.Servers.UDP.stop(server)
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
    assert_events_received(events)
  end

  defp assert_events_received(events) do
    receive do
      {msg, :udp} -> assert Event.list_to_events(events) == Msg.decode(msg).events
    after 10_000 -> flunk()
    end
  end
end

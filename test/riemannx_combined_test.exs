defmodule RiemannxTest.Combined do
  use ExUnit.Case, async: false
  alias Riemannx.Proto.Msg
  alias Riemannx.Proto.Event

  setup_all do
    Application.load(:riemannx)
    Application.put_env(:riemannx, :worker_module, Riemannx.Connections.Combined)
    :ok
  end

  setup do
    {:ok, tcp_server} = RiemannxTest.Servers.TCP.start(self())
    {:ok, udp_server} = RiemannxTest.Servers.UDP.start(self())
    Application.ensure_all_started(:riemannx)

    on_exit(fn() ->
      Application.stop(:riemannx)
      RiemannxTest.Servers.TCP.stop(tcp_server)
      RiemannxTest.Servers.UDP.stop(udp_server)
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
    :poolboy.transaction(
      :riemannx_pool,
      fn(pid) -> GenServer.call(pid, {:max_udp_size, 1}) end,
      :infinity
    )
    Riemannx.send_async(events)
    assert_events_received(events, :tcp)
  end

  defp assert_events_received(events) do
    receive do
      {msg, x} ->
        if byte_size(msg) > Application.get_env(:riemannx, :max_udp_size, 16384) do
          assert x == :tcp
          assert Event.list_to_events(events) == Msg.decode(msg).events
        else
          assert x == :udp
          assert Event.list_to_events(events) == Msg.decode(msg).events
        end          
    after 10_000 -> flunk()
    end
  end
  defp assert_events_received(events, x) do
    receive do
      {msg, ^x} -> assert Event.list_to_events(events) == Msg.decode(msg).events
    after 10_000 -> flunk()
    end
  end
end

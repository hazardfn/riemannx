defmodule RiemannxTest.TCP do
  use ExUnit.Case, async: false
  use PropCheck
  alias Riemannx.Proto.Msg
  alias Riemannx.Connections.TCP, as: Client
  alias RiemannxTest.Servers.TCP, as: Server
  alias RiemannxTest.Property.RiemannXPropTest, as: Prop

  setup_all do
    Application.load(:riemannx)
    Application.put_env(:riemannx, :type, :tcp)
    Application.put_env(:riemannx, :max_udp_size, 16384)
    :ok
  end

  setup do
    {:ok, server} = Server.start(self())
    Application.ensure_all_started(:riemannx)
    Application.put_env(:riemannx, :max_udp_size, 16384)

    on_exit(fn() ->
      Server.stop(server)
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

  test "Test connection retry raises eventually" do
    Application.put_env(:riemannx, :retry_count, 1)
    Application.put_env(:riemannx, :retry_interval, 1)
    conn = %Riemannx.Connection{
      host: "localhost",
      tcp_port: 5554
    }
    assert_raise RuntimeError, fn() ->
      Client.handle_cast(:init, conn)
    end
  end

  @tag :error
  test "Send failure is captured and returned on sync send" do
    conn = %Riemannx.Connection{
      host: "localhost" |> to_charlist,
      tcp_port: 5554,
      #:erlang.list_to_port is better but only in 20.
      socket: RiemannxTest.Utils.term_to_port("#Port<0.9999>")
    }
    refute :ok == Client.handle_call({:send_msg, <<>>}, self(), conn)
  end

  property "All reasonable metrics", [:verbose] do
    numtests(250, forall events in Prop.encoded_events() do
        events = Prop.deconstruct_events(events)
        Riemannx.send_async(events)
        (__MODULE__.assert_events_received(events) == true)
    end)
  end

  property "All reasonable metrics sync", [:verbose] do
    numtests(250, forall events in Prop.encoded_events() do
        events = Prop.deconstruct_events(events)
        :ok = Riemannx.send(events)
        (__MODULE__.assert_events_received(events) == true)
    end)
  end

  def assert_events_received(events) do
    msg     = Riemannx.create_events_msg(events) |> Msg.decode()
    events  = msg.events |> Enum.map(fn(e) -> %{e | time: 0} end)
    msg     = %{msg | events: events}
    encoded = Msg.encode(msg)
    receive do
      {^encoded, :tcp} -> true
    after
      10_000 -> false
    end
  end
end

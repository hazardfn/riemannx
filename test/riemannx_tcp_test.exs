defmodule RiemannxTest.TCP do
  use ExUnit.Case, async: false
  use PropCheck
  alias Riemannx.Proto.Msg
  alias RiemannxTest.Utils
  alias Riemannx.Connections.TCP, as: Client
  alias RiemannxTest.Server, as: Server
  alias RiemannxTest.Property.RiemannXPropTest, as: Prop
  alias Riemannx.Proto.Event
  alias Riemannx.Connection

  setup_all do
    Application.load(:riemannx)
    Application.put_env(:riemannx, :type, :tcp)
    on_exit(fn() ->
      Application.unload(:riemannx)
    end)
    :ok
  end

  setup do
    Utils.update_setting(:tcp, :port, 5555)
    {:ok, server} = Server.start(:tcp, self())
    Application.ensure_all_started(:riemannx)

    on_exit(fn() ->
      Server.stop(:tcp)
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
    Utils.update_setting(:tcp, :retry_count, 1)
    Utils.update_setting(:tcp, :retry_interval, 1)
    Utils.update_setting(:tcp, :port, 5554)
    conn = %Connection{
      host: to_charlist("localhost"),
      port: 5554
    }
    assert_raise RuntimeError, fn() ->
      Client.handle_cast(:init, conn)
    end
  end

  test "Send failure is captured and returned on sync send" do
    Utils.update_setting(:tcp, :port, 5554)
    conn = %Connection{
      host: to_charlist("localhost"),
      port: 5554,
      #:erlang.list_to_port is better but only in 20.
      socket: Utils.term_to_port("#Port<0.9999>")
    }
    refute :ok == Client.handle_call({:send_msg, <<>>}, self(), conn)
  end

  test "Send failure is captured and returned on query" do
    Utils.update_setting(:tcp, :port, 5554)
    conn = %Connection{
      host: to_charlist("localhost"),
      port: 5554,
      #:erlang.list_to_port is better but only in 20.
      socket: Utils.term_to_port("#Port<0.9999>")
    }
    refute :ok == Client.handle_call({:send_msg, <<>>, self()}, self(), conn)
  end

  test "Can query events" do
    event = [
      service: "riemannx-elixir",
      metric: 1,
      attributes: [a: 1],
      description: "test"
    ]
    event = Msg.decode(Riemannx.create_events_msg(event)).events
    msg   = Msg.new(ok: true, events: event)
    msg   = Msg.encode(msg)

    Server.set_response(:tcp, msg)
    events = Riemannx.query("test")
    assert events == Event.deconstruct(event)
  end

  test "Can query events w/ charlist" do
    event = [
      service: "riemannx-elixir",
      metric: 1,
      attributes: [a: 1],
      description: "test"
    ]
    event = Msg.decode(Riemannx.create_events_msg(event)).events
    msg   = Msg.new(ok: true, events: event)
    msg   = Msg.encode(msg)

    Server.set_response(:tcp, msg)
    events = Riemannx.query('test')
    assert events == Event.deconstruct(event)
  end

  test "Errors are handled in query" do
    event = [
      service: "riemannx-elixir",
      metric: 1,
      attributes: [a: 1],
      description: "test"
    ]
    event = Msg.decode(Riemannx.create_events_msg(event)).events
    msg   = Msg.new(ok: false, events: event)
    msg   = Msg.encode(msg)

    Server.set_response(:tcp, msg)
    events = Riemannx.query("test")
    assert match?([error: _e, message: _msg], events)
  end

  test "Empty queries are handled" do
    msg = Msg.encode(Msg.new(ok: true))

    Server.set_response(:tcp, msg)
    events = Riemannx.query("test")
    assert match?([], events)
  end

  test "Metrics sent on async send" do
    event = [
      service: "riemannx-elixir",
      metric: 1,
      attributes: [a: 1],
      description: "test"
    ]
    enc_event = Riemannx.create_events_msg(event)
    size      = byte_size(enc_event)
    Application.put_env(:riemannx, :metrics_module, RiemannxTest.Metrics.Test)
    Application.put_env(:riemannx, :test_pid, self())
    Riemannx.send_async(event)
    assert_receive(^size)
  end

  test "Metrics sent on sync send" do
    event = [
      service: "riemannx-elixir",
      metric: 1,
      attributes: [a: 1],
      description: "test"
    ]
    enc_event = Riemannx.create_events_msg(event)
    size      = byte_size(enc_event)
    Application.put_env(:riemannx, :metrics_module, RiemannxTest.Metrics.Test)
    Application.put_env(:riemannx, :test_pid, self())
    Riemannx.send(event)
    assert_receive(^size)
  end

  property "All reasonable metrics", [:verbose] do
    numtests(100, forall events in Prop.encoded_events() do
        events = Prop.deconstruct_events(events)
        Riemannx.send_async(events)
        (__MODULE__.assert_events_received(events) == true)
    end)
  end

  property "All reasonable metrics sync", [:verbose] do
    numtests(100, forall events in Prop.encoded_events() do
        events = Prop.deconstruct_events(events)
        :ok = Riemannx.send(events)
        (__MODULE__.assert_events_received(events) == true)
    end)
  end

  def assert_events_received(events) do
    msg     = Msg.decode(Riemannx.create_events_msg(events))
    events  = Enum.map(msg.events, fn(e) -> %{e | time: 0} end)
    msg     = %{msg | events: events}
    encoded = Msg.encode(msg)
    receive do
      {^encoded, :tcp} -> true
    after
      10_000 -> false
    end
  end
end

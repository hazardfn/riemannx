defmodule RiemannxTest.TLS do
  use ExUnit.Case, async: false
  use PropCheck
  alias Riemannx.Proto.Msg
  alias RiemannxTest.Server
  alias RiemannxTest.Utils
  alias Riemannx.Connections.TLS, as: Client
  alias RiemannxTest.Property.RiemannXPropTest, as: Prop

  setup_all do
    Application.load(:riemannx)
    Application.put_env(:riemannx, :type, :tls)
    Utils.update_setting(:tls, :options, [
      keyfile: "test/certs/client/key.pem",
      certfile: "test/certs/client/cert.pem",
      server_name_indication: :disable
    ])
    Utils.update_setting(:tls, :port, 5554)
  end

  setup do
    {:ok, server} = Server.start(:tls, self())
    Application.ensure_all_started(:riemannx)
    Utils.update_setting(:tls, :port, 5554)

    on_exit(fn() ->
      Server.stop(:tls)
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
    Utils.update_setting(:tls, :retry_count, 1)
    Utils.update_setting(:tls, :retry_interval, 1)
    Utils.update_setting(:tls, :port, 5556)
    conn = %Riemannx.Connection{
      host: to_charlist("localhost"),
      port: 5556
    }
    assert_raise RuntimeError, fn() ->
      Client.handle_cast(:init, conn)
    end
  end

  test "Send failure is captured and returned on sync send", context do
    conn = %Riemannx.Connection{
      host: to_charlist("localhost"),
      port: 5553,
      socket: :sys.get_state(context[:server]).socket
    }
    GenServer.call(context[:server], :cleanup)
    refute :ok == Client.handle_call({:send_msg, <<>>}, self(), conn)
  end

  @tag :broke
  test "Send failure is captured and returned on query", context do
    conn = %Riemannx.Connection{
      host: to_charlist("localhost"),
      port: 55,
      #:erlang.list_to_port is better but only in 20.
      socket: :sys.get_state(context[:server]).socket
    }
    GenServer.call(context[:server], :cleanup)
    refute :ok == Client.handle_call({:send_msg, 'wrong', self()}, self(), conn)
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

    RiemannxTest.Server.set_response(:tls, msg)
    events = Riemannx.query("test")
    assert events == Riemannx.Proto.Event.deconstruct(event)
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

    Server.set_response(:tls, msg)
    events = Riemannx.query("test")
    assert match?([error: _e, message: _msg], events)
  end

  test "Empty queries are handled" do
    msg = Msg.encode(Msg.new(ok: true))

    Server.set_response(:tls, msg)
    events = Riemannx.query("test")
    assert match?([], events)
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
    msg     = events |> Riemannx.create_events_msg() |> Msg.decode()
    events  = Enum.map(msg.events, fn(e) -> %{e | time: 0} end)
    msg     = %{msg | events: events}
    encoded = Msg.encode(msg)
    receive do
      {^encoded, :ssl} -> true
    after
      10_000 -> false
    end
  end
end

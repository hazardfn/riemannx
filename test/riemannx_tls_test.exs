defmodule RiemannxTest.TLS do
  use ExUnit.Case, async: false
  use PropCheck
  alias Riemannx.Proto.Msg
  alias Riemannx.Connections.TLS, as: Client
  alias RiemannxTest.Servers.TLS, as: Server
  alias RiemannxTest.Property.RiemannXPropTest, as: Prop

  setup_all do
    Application.load(:riemannx)
    Application.put_env(:riemannx, :type, :tls)
    Application.put_env(:riemannx, :ssl_opts, [
      keyfile: "test/certs/client/key.pem",
      certfile: "test/certs/client/cert.pem",
      server_name_indication: :disable
    ])
    Application.put_env(:riemannx, :tcp_port, 5554)
    Application.put_env(:riemannx, :max_udp_size, 16384)
    on_exit(fn() ->
      Application.unload(:riemannx)
    end)
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

  @tag :tls
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
      tcp_port: 5556
    }
    assert_raise RuntimeError, fn() ->
      Client.handle_cast(:init, conn)
    end
  end

  test "Send failure is captured and returned on sync send", context do
    conn = %Riemannx.Connection{
      host: "localhost" |> to_charlist,
      tcp_port: 5553,
      socket: :sys.get_state(context[:server]).socket
    }
    GenServer.call(context[:server], :cleanup)
    refute :ok == Client.handle_call({:send_msg, <<>>}, self(), conn)
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
    msg     = Riemannx.create_events_msg(events) |> Msg.decode()
    events  = msg.events |> Enum.map(fn(e) -> %{e | time: 0} end)
    msg     = %{msg | events: events}
    encoded = Msg.encode(msg)
    receive do
      {^encoded, :ssl} -> true
    after
      10_000 -> false
    end
  end
end

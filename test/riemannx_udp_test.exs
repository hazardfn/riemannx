defmodule RiemannxTest.UDP do
  use ExUnit.Case, async: false
  use PropCheck
  import Riemannx.Settings
  alias Riemannx.Proto.Msg
  alias Riemannx.Connections.UDP, as: Client
  alias RiemannxTest.Servers.UDP, as: Server
  alias RiemannxTest.Property.RiemannXPropTest, as: Prop

  setup_all do
    Application.load(:riemannx)
    Application.put_env(:riemannx, :type, :udp)
    Application.put_env(:riemannx, :max_udp_size, 16_384)
    on_exit(fn() ->
      Application.unload(:riemannx)
    end)
    :ok
  end

  setup do
    {:ok, server} = Server.start(self())
    Application.ensure_all_started(:riemannx)
    Application.put_env(:riemannx, :max_udp_size, 16_384)

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

  test "send_async/1 ignores UDP requests over the limit" do
    event = [
      service: "riemannx-elixir",
      metric: 1,
      attributes: [a: 1],
      description: "test"
    ]
    Application.put_env(:riemannx, :max_udp_size, 1)
    Riemannx.send_async(event)
    assert refute_events_received()
    Application.put_env(:riemannx, :max_udp_size, 16_384)
  end

  test "send/1 ignores UDP requests over the limit" do
    event = [
      service: "riemannx-elixir",
      metric: 1,
      attributes: [a: 1],
      description: "test"
    ]
    Application.put_env(:riemannx, :max_udp_size, 1)
    refute :ok == Riemannx.send(event)
    Application.put_env(:riemannx, :max_udp_size, 16_384)
  end

  test "sync message to a dead server causes an error" do
    event = [
      service: "riemannx-elixir",
      metric: 1,
      attributes: [a: 1],
      description: "test"
    ]
    :poolboy.transaction(:riemannx_pool, fn(pid) ->
      socket = :sys.get_state(pid).socket
      :gen_udp.close(socket)
    end)
    refute :ok == Riemannx.send(event)
    assert refute_events_received()
  end

  test "Send failure is captured and returned on sync send" do
    conn = %Riemannx.Connection{
      host: "localhost" |> to_charlist,
      udp_port: 5554,
      max_udp_size: 100,
      #:erlang.list_to_port is better but only in 20.
      socket: RiemannxTest.Utils.term_to_port("#Port<0.9000>")
    }
    refute :ok == Client.handle_call({:send_msg, <<>>}, self(), conn)
  end

  property "All reasonable metrics", [:verbose] do
    numtests(100, forall events in Prop.udp_events(max_udp_size()) do
        events = Prop.deconstruct_events(events)
        Riemannx.send_async(events)
        (__MODULE__.assert_events_received(events) == true)
    end)
  end

  property "All reasonable metrics sync", [:verbose] do
    numtests(100, forall events in Prop.udp_events(max_udp_size()) do
        events = Prop.deconstruct_events(events)
        :ok = Riemannx.send(events)
        (__MODULE__.assert_events_received(events) == true)
    end)
  end

  def refute_events_received() do
    receive do
      {<<>>, :udp} -> refute_events_received()
      {_, :udp} -> false
    after
      500 -> true
    end
  end
  def assert_events_received(events) do
    msg     = events |> Riemannx.create_events_msg() |> Msg.decode()
    events  = Enum.map(msg.events, fn(e) -> %{e | time: 0} end)
    msg     = %{msg | events: events}
    encoded = Msg.encode(msg)
    receive do
      {^encoded, :udp} -> true
    after
      10_000 -> false
    end
  end
end

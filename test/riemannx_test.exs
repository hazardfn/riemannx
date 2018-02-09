defmodule RiemannxTest do
  use ExUnit.Case, async: false
  alias Riemannx.Errors.InvalidMetricError
  alias Riemannx.Connection
  alias Riemannx.Settings
  alias RiemannxTest.Utils
  alias Riemannx.Proto.Event
  alias Riemannx.Proto.Msg

  test "Invalid events trigger an error" do
    assert_raise InvalidMetricError, fn ->
      Riemannx.send_async(metric: "NaN")
    end
  end

  test "Query return values" do
    assert Msg.decode(Connection.query_ok()) == Msg.new(ok: true)
    assert Msg.decode(Connection.query_failed()) == Msg.new(ok: false)
  end

  test "Setting a host name returns an event with that host" do
    event = [
      service: "riemannx-elixir",
      metric: 1,
      attributes: [a: 1],
      description: "test"
    ]

    Application.put_env(:riemannx, :event_host, "test_host")

    host =
      event
      |> Event.list_to_events()
      |> hd()
      |> Map.get(:host, nil)

    assert("test_host" == host)
  end

  test "Assigning max priority rasies a runtime error" do
    Utils.update_setting(:tcp, :priority, :max)
    assert_raise(RuntimeError, fn -> Settings.priority!(:tcp) end)
    Utils.update_setting(:tcp, :priority, :normal)
  end

  test "Assigning a random priority raises a runtime error" do
    Utils.update_setting(:tcp, :priority, :random)
    assert_raise(RuntimeError, fn -> Settings.priority!(:tcp) end)
    Utils.update_setting(:tcp, :priority, :normal)
  end

  test "Setting incompatible types causes an error" do
    Application.load(:riemannx)
    Application.put_env(:riemannx, :type, :batch)
    Utils.update_batch_setting(:type, :batch)
    Application.stop(:riemannx)
    {:error, {_, {_, {_, {_, {e, _}}}}}} = Application.ensure_all_started(:riemannx)
    Utils.update_batch_setting(:type, :combined)
    Application.ensure_all_started(:riemannx)
    assert e.message =~ "not supported"
  end

  test "Interval returns correct values" do
    Utils.update_batch_setting(:interval, {1, :seconds})
    assert Settings.batch_interval() == 1000

    Utils.update_batch_setting(:interval, {1, :milliseconds})
    assert Settings.batch_interval() == 1

    Utils.update_batch_setting(:interval, {1, :minutes})
    assert Settings.batch_interval() == 60_000
  end

  test "Time is not overwritten if set" do
    event = [
      service: "riemannx-elixir",
      metric: 1,
      attributes: [a: 1, keep_time: true],
      description: "test"
    ]

    time = :erlang.system_time(:seconds)
    micro_time = :erlang.system_time(:micro_seconds)
    event_time = Keyword.put(event, :time, time)
    event_micro = Keyword.put(event, :time_micros, micro_time)

    time_from_event =
      event_time
      |> Event.list_to_events()
      |> hd()
      |> Map.get(:time)

    m_time_from_event =
      event_micro
      |> Event.list_to_events()
      |> hd()
      |> Map.get(:time_micros)

    assert time_from_event == time
    assert m_time_from_event == micro_time
  end

  @tag :time
  test "Micro-time is used if set to true, time is set otherwise" do
    ## Default is use_micro: true
    event = [
      service: "riemannx-elixir",
      metric: 1,
      attributes: [a: 1, keep_time: true],
      description: "test"
    ]

    time_from_event =
      event
      |> Event.list_to_events()
      |> hd()
      |> Map.get(:time)

    micro_from_event =
      event
      |> Event.list_to_events()
      |> hd()
      |> Map.get(:time_micros)

    assert time_from_event == nil
    assert is_integer(micro_from_event)

    Application.put_env(:riemannx, :use_micro, false)

    time_from_event =
      event
      |> Event.list_to_events()
      |> hd()
      |> Map.get(:time)

    micro_from_event =
      event
      |> Event.list_to_events()
      |> hd()
      |> Map.get(:time_micros)

    assert is_integer(time_from_event)
    assert micro_from_event == nil

    Application.put_env(:riemannx, :use_micro, true)
  end
end

defmodule RiemannxTest.Legacy.RiemannxTest do
  use ExUnit.Case, async: false
  alias Riemannx.Errors.InvalidMetricError
  alias Riemannx.Proto.Event
  alias Riemannx.Proto.Msg
  alias Riemannx.Connection
  import Riemannx.Settings

  setup_all do
    Application.put_env(:riemannx, :settings_module, Riemannx.Settings.Legacy)
    :ok
  end

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
    Application.put_env(:riemannx, :priority, :max)
    assert_raise(RuntimeError, fn -> priority!(:tcp) end)
    Application.put_env(:riemannx, :priority, :normal)
  end

  test "Assigning a random priority raises a runtime error" do
    Application.put_env(:riemannx, :priority, :random)
    assert_raise(RuntimeError, fn -> priority!(:tcp) end)
    Application.put_env(:riemannx, :priority, :normal)
  end
end

defmodule RiemannxTest do
  use ExUnit.Case, async: false
  alias Riemannx.Errors.InvalidMetricError
  alias Riemannx.Proto.Event
  alias Riemannx.Proto.Msg

  test "Invalid events trigger an error" do
    assert_raise InvalidMetricError, fn ->
      Riemannx.send_async(metric: "NaN")
    end
  end

  test "Query return values" do
    assert Msg.decode(Riemannx.Connection.query_ok()) == Msg.new(ok: true)
    assert Msg.decode(Riemannx.Connection.query_failed()) == Msg.new(ok: false)
  end

  test "Setting a host name returns an event with that host" do
    event = [
      service: "riemannx-elixir",
      metric: 1,
      attributes: [a: 1],
      description: "test"
    ]
    Application.put_env(:riemannx, :event_host, "test_host")
    host = event
    |> Event.list_to_events()
    |> hd()
    |> Map.get(:host, nil)

    assert("test_host" == host)
  end
end

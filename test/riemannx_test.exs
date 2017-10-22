defmodule RiemannxTest do
  use ExUnit.Case, async: false
  alias Riemannx.Errors.InvalidMetricError
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
end

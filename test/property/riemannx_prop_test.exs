defmodule RiemannxTest.Property.RiemannXPropTest do
  use PropCheck
  alias Riemannx.Proto.Msg

  def events() do
    non_empty(
      list([service: elixir_string(),
            metric: integer(),
            attributes: list({atom(), atom()}),
            description: elixir_string()]))
  end
  def encoded_events() do
    let events <- events() do
      Riemannx.create_events_msg(events)
    end
  end

  def udp_events(max_size) do
    such_that events <- encoded_events(), when: byte_size(events) <= max_size
  end

  def realistic_text do
    list(frequency([{80, range(?a, ?z)},
                    {10, ?\s},
                    {1,  ?\n},
                    {1, oneof([?., ?-, ?!, ??, ?,])},
                    {1, range(?0, ?9)}
                  ]))
  end
  def elixir_string() do
    let t <- realistic_text() do
      to_string(t)
    end
  end

  def deconstruct_events(events) do
    events = events
    |> Msg.decode()
    |> Map.fetch!(:events)
    |> Enum.map(fn(e) -> Map.to_list(Map.delete(e, :__struct__)) end)

    attributes = events
    |> Enum.map(fn(event) ->
      event
      |> Keyword.get(:attributes, [])
      |> Enum.reduce([], fn(a, acc) ->
        Keyword.put(acc, String.to_atom(a.key), String.to_atom(a.value))
      end)
    |> List.flatten()
    end)
    |> List.flatten()

    Enum.flat_map(events, fn(kw) ->
      Keyword.put(kw, :attributes, attributes)
    end)
  end
end

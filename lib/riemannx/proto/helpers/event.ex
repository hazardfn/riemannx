defmodule Riemannx.Proto.Helpers.Event do
  @moduledoc false

  alias Riemannx.Proto.Attribute
  alias Riemannx.Errors.InvalidMetricError
  alias Riemannx.Settings

  defmacro __using__(_opts) do
    quote do
      alias Riemannx.Proto.Attribute

      # is_list(hd(list)) detects when it's a list of events, since keyword
      # events are also lists
      # [[service: "a", metric: 1], %{service: "b", metric: 2}]
      def list_to_events(list) when is_list(hd(list)) or is_map(hd(list)) do
        Enum.map(list, &build/1)
      end

      # [service: "a", metric: 1]
      def list_to_events(keyword) do
        list_to_events([keyword])
      end

      def build(dict) do
        # Note: unquote(__MODULE__) is the module that's defined in this file
        # and __MODULE__ is the module that's using this module.
        unquote(__MODULE__).build(dict, __MODULE__)
      end

      def deconstruct(events) when is_list(events) do
        Enum.map(events, &deconstruct/1)
      end

      def deconstruct(%{metric_sint64: int} = event) when is_integer(int),
        do: deconstruct(event, int)

      def deconstruct(%{metric_d: double} = event) when is_float(double),
        do: deconstruct(event, double)

      def deconstruct(%{metric_f: float} = event) when is_float(float),
        do: deconstruct(event, float)

      def deconstruct(event), do: deconstruct(event, nil)

      def deconstruct(event, metric) do
        attributes =
          Enum.reduce(event.attributes, %{}, &Map.put(&2, &1.key, &1.value))

        event
        |> Map.from_struct()
        |> Map.put(:metric, metric)
        |> Map.delete(:metric_d)
        |> Map.delete(:metric_f)
        |> Map.delete(:metric_sint64)
        |> Map.put(:attributes, attributes)
      end
    end
  end

  def build(args, mod) do
    args
    |> Enum.into(%{})
    |> Map.put_new_lazy(:time_micros, fn ->
      :erlang.system_time(:micro_seconds)
    end)
    |> Map.put_new_lazy(:time, fn -> :erlang.system_time(:seconds) end)
    |> Map.put_new_lazy(:host, &Settings.events_host/0)
    |> set_attributes_field
    |> set_metric_pb_fields
    |> Map.to_list()
    |> mod.new()
  end

  defp set_attributes_field(%{attributes: a} = map) when not is_nil(a) do
    Map.put(map, :attributes, Attribute.build(a))
  end

  defp set_attributes_field(map), do: map

  defp set_metric_pb_fields(%{metric: i} = map) when is_integer(i) do
    Map.put(map, :metric_sint64, i)
  end

  defp set_metric_pb_fields(%{metric: f} = map) when is_float(f) do
    Map.put(map, :metric_d, f)
  end

  defp set_metric_pb_fields(%{metric: m}) when not is_nil(m) do
    raise InvalidMetricError, metric: m
  end

  defp set_metric_pb_fields(map), do: map
end

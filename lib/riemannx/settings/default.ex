defmodule Riemannx.Settings.Default do
  @moduledoc """
  This module follows the default config format as of 3.0.0.
  """
  import Application
  alias Riemannx.Metrics.Default
  alias Riemannx.Queues
  @types [:tls, :tcp, :udp]

  # ===========================================================================
  # Behaviour
  # ===========================================================================
  @behaviour Riemannx.Settings

  # ===========================================================================
  # Types
  # ===========================================================================
  @type conn_type :: :tcp | :udp | :tls

  # ===========================================================================
  # API
  # ===========================================================================
  @spec pool_name(conn_type()) :: atom()
  def pool_name(:tcp), do: :riemannx_tcp
  def pool_name(:tls), do: :riemannx_tls
  def pool_name(:udp), do: :riemannx_udp

  @spec pool_size(conn_type()) :: non_neg_integer()
  def pool_size(t) when t in @types, do: extract(t, :pool_size, 2)

  @spec strategy(conn_type()) :: :fifo | :lifo
  def strategy(t) when t in @types, do: extract(t, :strategy, :fifo)

  @spec max_overflow(conn_type()) :: non_neg_integer()
  def max_overflow(t) when t in @types, do: extract(t, :max_overflow, 2)

  @spec checkout_timeout() :: non_neg_integer()
  def checkout_timeout, do: get_env(:riemannx, :checkout_timeout, 5_000)

  @spec type() :: conn_type() | :combined
  def type, do: get_env(:riemannx, :type, :combined)

  @spec module(conn_type() | :combined) :: module()
  def module(t) do
    case t do
      :tcp -> Riemannx.Connections.TCP
      :udp -> Riemannx.Connections.UDP
      :tls -> Riemannx.Connections.TLS
      :combined -> Riemannx.Connections.Combined
    end
  end

  @spec send_timeout() :: non_neg_integer()
  def send_timeout, do: get_env(:riemannx, :send_timeout, 5) * 1000

  @spec metrics_module() :: module()
  def metrics_module, do: get_env(:riemannx, :metrics_module, Default)

  @spec host() :: String.t()
  def host, do: get_env(:riemannx, :host, "localhost")

  @spec port(:tcp | :udp | :tls) :: :inet.port_number()
  def port(t), do: extract(t, :port, 5555)

  @spec max_udp_size() :: non_neg_integer()
  def max_udp_size, do: extract(:udp, :max_size, 16_384)

  @spec retry_count(conn_type()) :: non_neg_integer() | :infinity
  def retry_count(t), do: extract(t, :retry_count, 5)

  @spec retry_interval(conn_type()) :: non_neg_integer()
  def retry_interval(t), do: extract(t, :retry_interval, 5000)

  @spec options(conn_type()) :: list()
  def options(:tls),
    do:
      extract(:tls, :options, []) ++
        [:binary, nodelay: true, packet: 4, active: true]

  def options(:tcp),
    do:
      extract(:tcp, :options, []) ++
        [:binary, nodelay: true, packet: 4, active: true]

  def options(:udp),
    do: extract(:udp, :options, []) ++ [:binary, sndbuf: max_udp_size()]

  @spec events_host() :: binary()
  def events_host do
    inet_host = inet_host()
    event_host = get_env(:riemannx, :event_host, nil)

    cond do
      inet_host != nil && event_host == nil ->
        inet_host

      event_host == nil && inet_host == nil ->
        {:ok, host} = :inet.gethostname()
        host = to_string(host)
        put_env(:riemannx, :inet_host, host)
        host

      true ->
        event_host
    end
  end

  @spec priority!(conn_type()) :: Riemannx.Settings.priority() | no_return()
  def priority!(t) when t in @types do
    case extract(t, :priority, :normal) do
      p when p in [:low, :normal, :high] -> p
      p when p in [:max] -> raise("You should NOT use the max priority!")
      p -> raise("#{inspect(p)} is not a valid priority!")
    end
  end

  @spec block_workers?() :: boolean()
  def block_workers?, do: get_env(:riemannx, :block_workers, false)

  @spec queue_enabled?() :: boolean()
  def queue_enabled?, do: get_env(:riemannx, :queue_enabled, true)

  @spec queue_module() :: module()
  def queue_module, do: extract_queue(:module, Queues.Default)

  @spec queue_size() :: integer()
  def queue_size, do: extract_queue(:size, 100)

  @spec queue_interval() :: integer()
  def queue_interval, do: interval(extract_queue(:interval, {10, :seconds}))
  defp interval({x, :minutes}), do: interval({x * 60, :seconds})
  defp interval({x, :seconds}), do: x * 1000
  defp interval({x, :milliseconds}), do: x

  @spec queue_opts() :: Keyword.t()
  def queue_opts, do: extract_queue(:module_opts, [])

  @spec queue_name() :: atom()
  def queue_name, do: extract_queue(:name, :riemannx_queue)

  # ===========================================================================
  # Private
  # ===========================================================================
  ## It's best nobody knows about this, it's internal.
  @spec inet_host() :: binary() | nil
  defp inet_host, do: get_env(:riemannx, :inet_host, nil)

  defp extract(t, opt, default) do
    kw = get_env(:riemannx, t, [])
    Keyword.get(kw, opt, default)
  end

  defp extract_queue(opt, default) do
    queue_settings = get_env(:riemannx, :queue_settings, [])
    Keyword.get(queue_settings, opt, default)
  end
end

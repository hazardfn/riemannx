defmodule Riemannx.Application do
  @moduledoc false
  import Riemannx.Settings
  require Logger
  use Application

  # ===========================================================================
  # Application API
  # ===========================================================================
  def start(_type, _args) do
    children =
      case type() do
        t when t == :combined ->
          combined_pool()

        t when t in [:tcp, :udp, :tls] ->
          single_pool(t)

        t ->
          raise("Type not supported #{inspect(t)}")
      end

    children = children ++ maybe_queue(queue_opts())

    opts = [
      strategy: :one_for_one,
      name: Riemannx.Supervisor,
      shutdown: :infinity
    ]

    Supervisor.start_link(children, opts)
  end

  # ===========================================================================
  # Private
  # ===========================================================================
  defp maybe_queue(opts) do
    [
      %{
        id: :riemannx_queue,
        start: {queue_module(), :start_link, [opts]}
      }
    ]
  end

  defp single_pool(t) do
    poolboy_config = [
      name: {:local, pool_name(t)},
      worker_module: module(t),
      size: pool_size(t),
      max_overflow: max_overflow(t),
      strategy: strategy(t)
    ]

    [:poolboy.child_spec(pool_name(t), poolboy_config, [])]
  end

  defp combined_pool do
    tcp_config = single_pool(:tcp)
    udp_config = single_pool(:udp)
    List.flatten([tcp_config, udp_config])
  end
end

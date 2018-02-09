defmodule Riemannx.Application do
  @moduledoc false
  alias Riemannx.Connections.Batch
  import Riemannx.Settings
  require Logger
  use Application

  # ===========================================================================
  # Application API
  # ===========================================================================
  def start(_type, _args) do
    type = {type(), batch_type()}

    children =
      case type do
        {:batch, t} when t in [:combined, :tcp, :udp, :tls] ->
          Batch.start_link([])
          if t == :combined, do: combined_pool(), else: single_pool(t)

        {t, _} when t in [:combined, :tcp, :udp, :tls] ->
          if t == :combined, do: combined_pool(), else: single_pool(t)

        t ->
          raise("Type combination not supported #{inspect(t)}")
      end

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

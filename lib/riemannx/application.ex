defmodule Riemannx.Application do
  @moduledoc false
  import Riemannx.Settings
  use Application

  def start(_type, _args) do
    type = type()
    children =
      if type == :combined, do: combined_pool(), else: single_pool(type)
      if type == :tls, do: :ssl.start()

    opts = [
      strategy: :one_for_one,
      name: Riemannx.Supervisor,
      shutdown: :infinity
    ]

    Supervisor.start_link(children, opts)
  end

  defp single_pool(:tcp) do
    poolboy_config = [
      name: {:local, pool_name(:tcp)},
      worker_module: module(:tcp),
      size: pool_size(:tcp),
      max_overflow: max_overflow(:tcp),
      strategy: strategy(:tcp)
    ]
    [:poolboy.child_spec(pool_name(:tcp), poolboy_config, [])]
  end
  defp single_pool(:udp) do
    poolboy_config = [
      name: {:local, pool_name(:udp)},
      worker_module: module(:udp),
      size: pool_size(:udp),
      max_overflow: max_overflow(:udp),
      strategy: strategy(:udp)
    ]
    [:poolboy.child_spec(pool_name(:udp), poolboy_config, [])]
  end
  defp single_pool(:tls) do
    poolboy_config = [
      name: {:local, pool_name(:tls)},
      worker_module: module(:tls),
      size: pool_size(:tls),
      max_overflow: max_overflow(:tls),
      strategy: strategy(:tls)
    ]
    [:poolboy.child_spec(pool_name(:tls), poolboy_config, [])]
  end

  defp combined_pool() do
    tcp_config = [
      name: {:local, pool_name(:tcp)},
      worker_module: Riemannx.Connections.TCP,
      size: pool_size(:tcp),
      max_overflow: max_overflow(:tcp),
      strategy: strategy(:tcp)
    ]
    udp_config = [
      name: {:local, pool_name(:udp)},
      worker_module: Riemannx.Connections.UDP,
      size: pool_size(:udp),
      max_overflow: max_overflow(:udp),
      strategy: strategy(:udp)
    ]
    [:poolboy.child_spec(pool_name(:tcp), tcp_config, []),
     :poolboy.child_spec(pool_name(:udp), udp_config, [])]
  end
end

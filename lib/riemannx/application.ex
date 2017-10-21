defmodule Riemannx.Application do
  @moduledoc false
  import Riemannx.Settings
  use Application

  def start(_type, _args) do
    conn = %Riemannx.Connection{
      host: host(),
      tcp_port: tcp_port(),
      udp_port: udp_port(),
      max_udp_size: max_udp_size(),
      key: key(),
      cert: cert(),
      verify_peer: verify_peer()
    }
    children =
      if type() == :combined, do: combined_pool(conn), else: single_pool(conn)
      if type() == :tls, do: :ssl.start()

    opts = [
      strategy: :one_for_one,
      name: Riemannx.Supervisor,
      shutdown: :infinity
    ]

    Supervisor.start_link(children, opts)
  end

  defp single_pool(conn) do
    poolboy_config = [
      name: {:local, pool_name()},
      worker_module: module(),
      size: pool_size(),
      max_overflow: max_overflow(),
      strategy: strategy()
    ]
    [:poolboy.child_spec(pool_name(), poolboy_config, conn)]
  end

  defp combined_pool(conn) do
    tcp_config = [
      name: {:local, :riemannx_tcp},
      worker_module: Riemannx.Connections.TCP,
      size: pool_size(),
      max_overflow: max_overflow(),
      strategy: strategy()
    ]
    udp_config = [
      name: {:local, :riemannx_udp},
      worker_module: Riemannx.Connections.UDP,
      size: pool_size(),
      max_overflow: max_overflow(),
      strategy: strategy()
    ]
    [:poolboy.child_spec(:riemannx_tcp, tcp_config, conn),
     :poolboy.child_spec(:riemannx_udp, udp_config, conn)]
  end
end

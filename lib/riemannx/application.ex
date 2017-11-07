defmodule Riemannx.Application do
  @moduledoc false
  import Riemannx.Settings
  use Application

  def start(_type, _args) do
    tcp_opts = Keyword.merge(tcp_default(), tcp())
    udp_opts = Keyword.merge(udp_default(), udp())
    Application.put_env(:riemannx, :tcp, tcp_opts)
    Application.put_env(:riemannx, :udp, udp_opts)
    conn = %Riemannx.Connection{
      host: host(),
      tcp: tcp_opts,
      udp: udp_opts,
      priority: priority!()
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

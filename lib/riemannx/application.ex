defmodule Riemannx.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    poolboy_config = [
      name: {:local, pool_name()},
      worker_module: worker_module(),
      size: pool_size(),
      max_overflow: max_overflow()
    ]    
    
    children = [
      :poolboy.child_spec(pool_name(), poolboy_config, [host: host(), 
                                                        tcp_port: tcp_port(), 
                                                        udp_port: udp_port(),
                                                        max_udp_size: max_udp_size()])
    ]
    
    opts = [
      strategy: :one_for_one, 
      name: Riemannx.Supervisor
    ]
    
    Supervisor.start_link(children, opts)
  end

  defp pool_name, do: :riemannx_pool
  defp pool_size, do: Application.get_env(:riemannx, :pool_size, 10)
  defp max_overflow, do: Application.get_env(:riemannx, :max_overflow, 20)
  defp worker_module, do: Application.get_env(:riemannx, :worker_module, Riemannx.Connections.Combined)
  defp host, do: Application.get_env(:riemannx, :host, "localhost")
  defp tcp_port, do: Application.get_env(:riemannx, :tcp_port, 5555)
  defp udp_port, do: Application.get_env(:riemannx, :udp_port, 5555)
  defp max_udp_size, do: Application.get_env(:riemannx, :max_udp_size, 16384)
end

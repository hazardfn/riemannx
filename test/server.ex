defmodule RiemannxTest.Server do
  @moduledoc """
  A simple behaviour module for implementing test servers.
  """

  # ===========================================================================
  # Callbacks
  # ===========================================================================
  @callback start(p :: pid()) :: {:ok, pid()} | any()
  @callback set_response(r :: any()) :: :ok
  @callback stop() :: :ok

  # ===========================================================================
  # API
  # ===========================================================================
  def start(type, return_pid), do: module(type).start(return_pid)
  def set_response(type, value), do: module(type).set_response(value)
  def stop(type), do: module(type).stop()

  # ===========================================================================
  # Private
  # ===========================================================================
  defp module(:tcp), do: RiemannxTest.Servers.TCP
  defp module(:tls), do: RiemannxTest.Servers.TLS
  defp module(:udp), do: RiemannxTest.Servers.UDP
end
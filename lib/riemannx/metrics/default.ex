defmodule Riemannx.Metrics.Default do
  @moduledoc """
  The default metrics backend which does nothing.
  """
  @behaviour Riemannx.Metrics

  # ===========================================================================
  # API
  # ===========================================================================
  def udp_message_sent(_), do: :ok
  def tcp_message_sent(_), do: :ok
  def tls_message_sent(_), do: :ok
end

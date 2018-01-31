defmodule Riemannx.Metrics do
  @moduledoc """
  This is the callback module for metrics, you can extend this to report
  metrics to any kind of metric software (graphite, influx etc.)
  """
  alias Riemannx.Settings

  # ===========================================================================
  # Callbacks
  # ===========================================================================
  @callback udp_message_sent(size :: non_neg_integer()) :: :ok
  @callback tcp_message_sent(size :: non_neg_integer()) :: :ok
  @callback tls_message_sent(size :: non_neg_integer()) :: :ok

  # ===========================================================================
  # Public API
  # ===========================================================================
  @spec udp_message_sent(non_neg_integer()) :: :ok
  def udp_message_sent(s), do: Settings.metrics_module().udp_message_sent(s)

  @spec tcp_message_sent(non_neg_integer()) :: :ok
  def tcp_message_sent(s), do: Settings.metrics_module().tcp_message_sent(s)

  @spec tls_message_sent(non_neg_integer()) :: :ok
  def tls_message_sent(s), do: Settings.metrics_module().tls_message_sent(s)
end

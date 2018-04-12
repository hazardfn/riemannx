defmodule Riemannx.Connections.Combined do
  @moduledoc """
  The combined connection worker works out when it's possible to use UDP and
  will transmit via TCP when the message size exceeds the total max byte size.

  This ensures you get the non-blocking behaviour of UDP without dropping
  events if they exceed the byte size configured on the Riemann server. This
  connection is the recommended default.

  ## Special Notes

  * The callback functions in this module simply route to the callback functions
  in either the TCP or UDP modules based on a simple byte_size check of the
  given event.

  * Even though this is the recommended default that is based on my use-case
  for this library. Your requirements may be VERY different. Using UDP at all
  is unreliable but in my use case I don't care if some events don't make it,
  in situations it is absolutely critical your events make it in order and
  reliably you should use TCP. In fact Riemann themeselves recommend TCP only.
  """
  @behaviour Riemannx.Connection

  import Riemannx.Settings
  alias Riemannx.Connections.TCP
  alias Riemannx.Connections.UDP

  # ===========================================================================
  # API
  # ===========================================================================
  def send(e, t), do: conn_module(e).send(e, t)
  def send_async(e), do: conn_module(e).send_async(e)
  def query(m, t), do: TCP.query(m, t)

  # ===========================================================================
  # Private
  # ===========================================================================
  defp conn_module(event) do
    if byte_size(event) > max_udp_size(), do: TCP, else: UDP
  end
end

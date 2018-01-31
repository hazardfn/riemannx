defmodule RiemannxTest.Metrics.Test do
  @moduledoc false
  def tcp_message_sent(s), do: Kernel.send(test_pid(), s)
  def udp_message_sent(s), do: Kernel.send(test_pid(), s)
  def tls_message_sent(s), do: Kernel.send(test_pid(), s)

  defp test_pid, do: Application.get_env(:riemannx, :test_pid, self())
end

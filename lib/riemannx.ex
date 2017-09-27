defmodule Riemannx do
  @moduledoc """
  Riemannx is a riemann client that supports UDP/TCP sockets and also supports
  a hybrid connection where smaller packets are sent via UDP and the rest over
  TCP.

  The Riemannx interface only supports asynchronous message sending because
  async is cool.

  For configuration instructions look at the individual connection modules.
  """
  alias Riemannx.Proto.Event
  alias Riemannx.Proto.Msg

  def send_async(events) do
    events 
    |> create_events_msg()
    |> enqueue()
  end

  defp create_events_msg(events) do
    [events: Event.list_to_events(events)]
    |> Msg.new
  end

  defp enqueue(message) do
    :poolboy.transaction(
      :riemannx_pool,
      fn(pid) -> GenServer.cast(pid, {:send_msg, message}) end,
      :infinity
    )
  end
end
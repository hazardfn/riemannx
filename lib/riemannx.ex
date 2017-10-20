defmodule Riemannx do
  @moduledoc """
  Riemannx is a riemann client that supports UDP/TCP sockets and also supports
  a hybrid connection where smaller packets are sent via UDP and the rest over
  TCP.

  For configuration instructions look at the individual connection modules.
  """
  alias Riemannx.Proto.Event
  alias Riemannx.Proto.Msg
  import Riemannx.Settings
  require Logger

  @type events :: [Keyword.t()] | Keyword.t()

  def send(events) do
    events
    |> create_events_msg()
    |> enqueue_sync()
  end

  def send_async(events) do
    events
    |> create_events_msg()
    |> enqueue()
  end

  def create_events_msg(events) do
    [events: Event.list_to_events(events)]
    |> Msg.new
    |> Msg.encode
  end

  defp enqueue_sync(message) do
    case Riemannx.Connection.get_worker(message) do
      worker when is_pid(worker) ->
        Riemannx.Connection.send(worker, message)
      error ->
        Logger.warn("""
          #{__MODULE__} | Received an error while fetching a worker, it's possible
          the data you were sending was too large for your chosen strategy:

          Error: #{inspect error}
          Type: #{inspect type()}

          If you see this log entry often you should maybe think about changing
          your strategy.
        """)
        error
    end
  end

  defp enqueue(message) do
    case Riemannx.Connection.get_worker(message) do
      worker when is_pid(worker) ->
        Riemannx.Connection.send_async(worker, message)
      error ->
        Logger.warn("""
          #{__MODULE__} | Received an error while fetching a worker, it's possible
          the data you were sending was too large for your chosen strategy:

          Error: #{inspect error}
          Type: #{inspect type()}

          If you see this log entry often you should maybe think about changing
          your strategy.
        """)
        :ok
    end
  end
end

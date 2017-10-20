defmodule Riemannx do
  @moduledoc """
  Riemannx is a riemann client that supports UDP/TCP sockets and also supports
  a hybrid connection where smaller packets are sent via UDP and the rest over
  TCP.

  ## Examples

  To use riemannx all you need to do is fill out some config entries - after
  that everything just happens automagically (save for the actual sending of
  course):

  ```
    config :riemannx, [
      # Client settings
      host: "127.0.0.1",
      tcp_port: 5555,
      udp_port: 5555,

      # Must be the same as server side, the default is riemann's default.
      max_udp_size: 16384,

      type: :combined,

      # How many times to re-attempt a TCP connection before crashing.
      retry_count: 5,

      # Interval to wait before the next TCP connection attempt.
      retry_interval: 1,

      # Poolboy settings
      pool_size: 5, # Pool size will be 10 if you use a combined type.
      max_overflow: 5, # Max overflow will be 10 if you use a combined type.
      strategy: :fifo # See Riemannx.Settings documentation for more info.
    ]
  ```

  Riemannx supports two `send` methods, one asynchronous the other synchronous:

  ### Synchronous Send

  Synchronous sending allows you to handle the errors that might occur during
  send, below is an example showing both how this error looks and what happens
  on a successful send:

  ```
  event = [service: "riemannx-elixir",
          metric: 1,
          attributes: [a: 1],
          description: "test"]

  case Riemannx.send(event) do
    :ok ->
      "Success!"

    [error: error, msg: encoded_msg] ->
      # The error will always be a string so you can output it as it is.
      #
      # The encoded message is a binary blob but you can use the riemannx proto
      # msg module to decode it if you wish to see it in human readable form.
      msg = encoded_msg |> Riemannx.Proto.Msg.decode()
  end
  ```

  ### Asynchronous Send

  Asynchronous sending is much faster but you never really know if your message
  made it, in a lot of cases this kind of sending is safe enough and for most
  use cases the recommended choice. It's fairly simple to implement:

  ```
  event = [service: "riemannx-elixir",
          metric: 1,
          attributes: [a: 1],
          description: "test"]

  Riemannx.send_async(event)

  # Who knows if it made it? Who cares? 60% of the time it works everytime!
  ```

  ### Important

  NOTE: If a worker is unable to send it will die and be restarted giving it
  a chance to return to a 'correct' state. On an asynchronous send this is done
  by pattern matching :ok with the send command, for synchronous sends if the
  return value is an error we kill the worker before returning the result.
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
        result = Riemannx.Connection.send(worker, message)
        unless result == :ok, do: GenServer.stop(worker, :unable_to_send)
        result
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

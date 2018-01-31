defmodule Riemannx do
  @moduledoc """
  Riemannx is a riemann client that supports UDP/TCP/TLS sockets and also supports
  a hybrid connection where smaller packets are sent via UDP and the rest over
  TCP.

  ## Examples

  To use riemannx all you need to do is fill out some config entries - after
  that everything just happens automagically (save for the actual sending of
  course):

  ```elixir
  config :riemannx, [
    host: "localhost", # The riemann server
    event_host: "my_app", # You can override the host name sent to riemann if you want (see: Host Injection)
    type: :combined, # The type of connection you want to run (:tcp, :udp, :tls or :combined)
    tcp: [
      port: 5555,
      retry_count: 5, # How many times to re-attempt a TCP connection
      retry_interval: 1000, # Interval to wait before the next TCP connection attempt (milliseconds).
      priority: :high, # Priority to give TCP workers.
      options: [], # Specify additional options to be passed to gen_tcp (NOTE: [:binary, nodelay: true, packet: 4, active: true] will be added to whatever you type here as they are deemed essential)
      pool_size: 5, # How many TCP workers should be in the pool.
      max_overflow: 5, # Under heavy load how many more TCP workers can be created to meet demand?
      strategy: :fifo # The poolboy strategy for retrieving workers from the queue
    ],
    udp: [
      port: 5555,
      priority: :high,
      options: [], # Specify additional options to be passed to gen_udp (NOTE: [:binary, sndbuf: max_udp_size()] will be added to whatever you type here as they are deemed essential)
      max_size: 16_384, # Maximum accepted packet size (this is configured in your Riemann server)
      pool_size: 5,
      max_overflow: 5,
      strategy: :fifo
    ],
    tls: [
      port: 5554,
      retry_count: 5, # How many times to re-attempt a TLS connection
      retry_interval: 1000, # Interval to wait before the next TLS connection attempt (milliseconds).
      priority: :high,
      options: [], # Specify additional options to be passed to :ssl (NOTE: [:binary, nodelay: true, packet: 4, active: true] will be added to whatever you type here as they are deemed essential)
      pool_size: 5,
      max_overflow: 5,
      strategy: :fifo
    ]
  ]
  ```

  ### Worker Behaviour

  If a worker is unable to send it will die and be restarted giving it
  a chance to return to a 'correct' state. On an asynchronous send this is done
  by pattern matching :ok with the send command, for synchronous sends if the
  return value is an error we kill the worker before returning the result.
  """
  alias Riemannx.Proto.Event
  alias Riemannx.Proto.Msg
  alias Riemannx.Proto.Query
  alias Riemannx.Connection, as: Conn
  import Riemannx.Settings

  # ===========================================================================
  # Types
  # ===========================================================================
  @type events :: [Keyword.t()] | Keyword.t()

  # ===========================================================================
  # API
  # ===========================================================================
  @doc """
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
  """
  @spec send(events) :: :ok | Conn.error()
  def send(events) do
    events
    |> create_events_msg()
    |> enqueue_sync()
  end

  @doc """
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
  """
  @spec send_async(events()) :: :ok
  def send_async(events) do
    events
    |> create_events_msg()
    |> enqueue()
  end

  @doc """
  Riemann has the concept of a queryable index which allows you to search for
  specific events, indexes must be specially created in your config otherwise
  the server will return a "no index" error.

  ```elixir
  # Lets send an event that we can then query
  Riemannx.send([service: "riemannx", metric: 5.0, attributes: [v: "2.2.0"]])

  # Let's fish it out
  events = Riemannx.query('service ~= "riemannx"')

  #  [%{attributes: %{"v" => "2.2.0"}, description: nil, host: _,
  #     metric: nil, service: "riemannx", state: nil, tags: [],
  #     time: _, ttl: _}]
  ```

  For more information on querying and the language features have a look at
  the [Core Concepts](http://riemann.io/concepts.html).
  """
  @spec query(String.t() | list(), timeout()) :: {:ok, events()} | Conn.error()
  def query(_q, _t \\ 5000)
  def query(query, timeout) when is_list(query) do
    query
    |> :erlang.list_to_binary
    |> query(timeout)
  end
  def query(query, timeout) when is_binary(query) do
    query = [query: Query.new(string: query)]
    query
    |> Msg.new()
    |> Msg.encode()
    |> enqueue_query(timeout)
  end

  @doc """
  Constructs a protobuf message based on an event or list of events.
  """
  def create_events_msg(events) do
    [events: Event.list_to_events(events)]
    |> Msg.new
    |> Msg.encode
  end

  # ===========================================================================
  # Private
  # ===========================================================================
  defp enqueue_query(message, timeout) do
    result = case type() do
      type when type in [:tls, :tcp] ->
        worker = Conn.get_worker(message)
        if is_pid(worker), do: Conn.query(worker, message, self())
      type when type in [:combined, :udp] ->
        Conn.query(nil, message, self())
    end
    if result == :ok do
      receive do
        {:ok, []}  -> []
        {:ok, msg} -> Event.deconstruct(msg.events)
        error      -> error
      after timeout -> [error: "Query timed out", message: message]
      end
    else
      result
    end
  end

  defp enqueue_sync(message) do
    case Conn.get_worker(message) do
      worker when is_pid(worker) ->
        result = Conn.send(worker, message)
        unless result == :ok, do: GenServer.stop(worker, :unable_to_send)
        result
      error ->
        error
    end
  end

  defp enqueue(message) do
    case Conn.get_worker(message) do
      worker when is_pid(worker) ->
        Conn.send_async(worker, message)
      _error ->
        :ok
    end
  end
end

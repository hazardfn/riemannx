defmodule Riemannx.Settings do
  @moduledoc """
  This is the callback module for settings, you can extend this if you wish to
  store your riemannx settings elsewhere like a database.
  """
  alias Riemannx.Settings.Default
  import Application

  # ===========================================================================
  # Types
  # ===========================================================================
  @type priority :: :low | :normal | :high
  @type conn_type :: :tcp | :udp | :tls

  # ===========================================================================
  # Callbacks
  # ===========================================================================
  @callback pool_name(t :: conn_type()) :: atom()
  @callback pool_size(t :: conn_type()) :: non_neg_integer()
  @callback strategy(t :: conn_type()) :: :fifo | :lifo
  @callback max_overflow(t :: conn_type()) :: non_neg_integer()
  @callback checkout_timeout() :: non_neg_integer()
  @callback type() :: conn_type() | :combined
  @callback module(conn_type() | :combined) :: module()
  @callback send_timeout() :: non_neg_integer()
  @callback metrics_module() :: module()
  @callback host() :: binary()
  @callback port(t :: conn_type()) :: :inet.port_number()
  @callback max_udp_size() :: non_neg_integer()
  @callback retry_count(t :: conn_type()) :: non_neg_integer() | :infinity
  @callback retry_interval(t :: conn_type()) :: non_neg_integer()
  @callback options(t :: conn_type()) :: list()
  @callback events_host() :: binary()
  @callback priority!(conn_type()) :: priority() | no_return()
  @callback block_workers?() :: boolean()
  @callback queue_enabled?() :: boolean()
  @callback queue_module() :: module()
  @callback queue_size() :: integer()
  @callback queue_interval() :: integer()
  @callback queue_opts() :: Keyword.t()
  @callback queue_name() :: atom()

  # ===========================================================================
  # API
  # ===========================================================================
  @doc """
  Pool name is the name of the poolboy pool, they MUST be unique for each
  connection type.

  Defaults:

  * tcp: `:riemannx_tcp`
  * tls: `:riemannx_tls`
  * udp: `:riemannx_udp`
  """
  @spec pool_name(conn_type()) :: atom()
  def pool_name(t), do: settings_module().pool_name(t)

  @doc """
  Pool size returns the set pool size given the connection type.

  Default: 10
  """
  @spec pool_size(conn_type()) :: non_neg_integer()
  def pool_size(t), do: settings_module().pool_size(t)

  @doc """
  The poolboy worker strategy, see the poolboy docs for more info on strategy.

  Default: `:fifo`
  """
  @spec strategy(conn_type()) :: :fifo | :lifo
  def strategy(t), do: settings_module().strategy(t)

  @doc """
  The max overflow for the poolboy pool, this value determines how many extra
  workers can be created under high load.

  Default: 20
  """
  @spec max_overflow(conn_type()) :: non_neg_integer()
  def max_overflow(t), do: settings_module().max_overflow(t)

  @doc """
  The maximum number of seconds to wait for a free worker before discarding data,
  :infinity is a valid value here and means you will wait for eternity for a
  free worker.

  Note that :infinity can cause a build-up of messages in your process inbox if
  using the batcher and your riemann instance experiences an outage!

  DATA MAY BE DISCARDED IF NO AVAILABLE WORKER IS PRESENT AFTER THIS TIMEOUT!

  Default: 5_000
  """
  @spec checkout_timeout() :: non_neg_integer()
  def checkout_timeout(), do: settings_module().checkout_timeout()

  @doc """
  Returns the connection type set (tls, tcp, udp, combined, batch).

  Default: `:combined`
  """
  @spec type() :: conn_type() | :combined
  def type, do: settings_module().type()

  @doc """
  Returns the correct connection backend based on the set type.

  Default: `Riemannx.Connections.Combined`
  """
  @spec module() :: module()
  def module, do: module(type())

  @doc """
  Returns the set metrics module.

  Default: `Riemannx.Metrics.Default`
  """
  @spec metrics_module() :: module()
  def metrics_module, do: settings_module().metrics_module()

  @doc """
  Returns the module related to the given type.
  """
  @spec module(conn_type()) :: module()
  def module(t), do: settings_module().module(t)

  @doc """
  Returns the timeout for sending a synchronous message, once the timeout is
  reached the riemannx batch connection will catch the error and try
  sending again. Other backends will error as normal. Give in seconds.

  Default: `5`
  """
  @spec send_timeout() :: non_neg_integer()
  def send_timeout, do: settings_module().send_timeout()

  @doc """
  Returns the riemann host.

  Default: localhost
  """
  @spec host() :: String.t()
  def host, do: settings_module().host()

  @doc """
  Returns the set port for the given connection type.

  Default: 5555
  """
  @spec port(conn_type()) :: :inet.port_number()
  def port(t), do: settings_module().port(t)

  @doc """
  Returns the maximum size allowed for a UDP packet.

  Default: 16_384
  """
  @spec max_udp_size() :: non_neg_integer()
  def max_udp_size, do: settings_module().max_udp_size()

  @doc """
  Returns the amount of times a worker should re-attempt a connection before
  giving up. You can set :infinity if you want to try until it's available.

  Default: 5
  """
  @spec retry_count(conn_type()) :: non_neg_integer() | :infinity
  def retry_count(t), do: settings_module().retry_count(t)

  @doc """
  Returns the time in milliseconds to wait between each connection re-attempt.

  Default: 5000
  """
  @spec retry_interval(conn_type()) :: non_neg_integer()
  def retry_interval(t), do: settings_module().retry_interval(t)

  @doc """
  Returns the options that will be passed to the underlying gen_tcp/udp/ssl
  server.

  NOTE: There are some things that will be appended to whatever you put in the
  options field as they are deemed essential to the operation of the library:

  * tcp: `[:binary, nodelay: true, packet: 4, active: true]`
  * tls: `[:binary, nodelay: true, packet: 4, active: true]`
  * udp: `[:binary, sndbuf: max_udp_size()]`

  Defaults:

  * tcp: []
  * tls: []
  * udp: []
  """
  @spec options(conn_type()) :: list()
  def options(t), do: settings_module().options(t)

  @doc """
  Returns the host name that will be appended to events.

  Default: derived using `:inets.gethostname`.
  """
  @spec events_host() :: binary()
  def events_host, do: settings_module().events_host()

  @doc """
  Returns the set priority for the workers based on type.

  Default: `:normal`
  """
  @spec priority!(conn_type()) :: priority() | no_return()
  def priority!(t), do: settings_module().priority!(t)

  @doc """
  Sets if a call to pick a worker from the pool should block until one is
  available.

  NOTE: Setting this to true can cause huge message queue build-ups if
  processing a large volume of data. Setting to false may cause loss of data
  unless you opt-in to using the data cache feature.

  Default: `false`
  """
  @spec block_workers?() :: boolean()
  def block_workers?, do: settings_module().block_workers?()

  @doc """
  Using the queue allows you to have non-blocking workers while retaining data
  during large bursts of messages. Messages will be placed in a queue, collected
  and pushed out.

  Use of the queue may reduce the number of times UDP is a viable protocol given
  the size of the assembled events.

  Default: `true`
  """
  @spec queue_enabled?() :: boolean()
  def queue_enabled?, do: settings_module().queue_enabled?()

  @doc """
  Returns the queue module, relevant if queuing enabled.

  Default: Riemannx.Queues.Default
  """
  @spec queue_module() :: module()
  def queue_module, do: settings_module().queue_module()

  @doc """
  Returns the max size the queue should be allowed to reach before
  flushing is considered below the interval threshold.

  Default: 100
  """
  @spec queue_size() :: integer()
  def queue_size, do: settings_module().queue_size()

  @doc """
  Returns the queue interval. This is the interval at which 'rejects' in the
  queue will be flushed to riemann.

  Default: {10, :seconds}
  """
  @spec queue_interval() :: integer()
  def queue_interval, do: settings_module().queue_interval()

  @doc """
  Queue opts will get passed to the start_link of the queue module given.

  Default: `[]`
  """
  @spec queue_opts() :: Keyword.t()
  def queue_opts, do: settings_module().queue_opts()

  @doc """
  Gets the process name of the queue.

  default `riemannx_queue`
  """
  @spec queue_name() :: atom()
  def queue_name, do: settings_module().queue_name()

  @doc """
  Returns the settings backend module you are using.

  Default: `Riemannx.Settings.Default`
  """
  @spec settings_module() :: module()
  def settings_module, do: get_env(:riemannx, :settings_module, Default)
end

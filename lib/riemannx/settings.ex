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
  @callback type() :: conn_type() | :combined | :batch
  @callback module(conn_type() | :combined | :batch) :: module()
  @callback batch_module() :: module()
  @callback batch_type() :: conn_type() | :combined
  @callback batch_size() :: integer()
  @callback batch_interval() :: integer()
  @callback metrics_module() :: module()
  @callback host() :: binary()
  @callback port(t :: conn_type()) :: :inet.port_number()
  @callback max_udp_size() :: non_neg_integer()
  @callback retry_count(t :: conn_type()) :: non_neg_integer() | :infinity
  @callback retry_interval(t :: conn_type()) :: non_neg_integer()
  @callback options(t :: conn_type()) :: list()
  @callback events_host() :: binary()
  @callback priority!(conn_type()) :: priority() | no_return()

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
  Returns the connection type set (tls, tcp, udp, combined, batch).

  Default: `:combined`
  """
  @spec type() :: conn_type() | :combined | :batch
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
  Returns the batch type, similar to `type()` but is used to provide a
  connection module to the batching wrapper.

  Default: :combined
  """
  @spec batch_type() :: conn_type() | :combined
  def batch_type, do: settings_module().batch_type()

  @doc """
  Returns the batch module, relevant if using the batching connection.

  Default: Riemannx.Connections.Combined
  """
  @spec batch_module() :: module()
  def batch_module, do: settings_module().batch_module()

  @doc """
  Returns the batch size.

  Default: 100
  """
  @spec batch_size() :: integer()
  def batch_size, do: settings_module().batch_size()

  @doc """
  Returns the batch interval.

  Default: {1, :minutes}
  """
  @spec batch_interval() :: integer()
  def batch_interval, do: settings_module().batch_interval()

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
  Returns the settings backend module you are using.

  Default: `Riemannx.Settings.Default`
  """
  @spec settings_module() :: module()
  def settings_module, do: get_env(:riemannx, :settings_module, Default)
end

defmodule Riemannx.Settings do
  @moduledoc """
  This is a utility module used to get settings as and when they are needed.

  View the documentation for the individual functions for more information
  about what they are.
  """
  import Application

  @doc """
  The name of the poolboy pool, for ease of use this is hard-coded to
  `:riemannx_pool`
  """
  @spec pool_name() :: :riemannx_pool
  def pool_name, do: :riemannx_pool

  @doc """
  The size of your worker pool, adjust to your requirements it's important
  not to have too many and maybe even more so to not have too little - a
  little trial and error tests should help you come to a reasonable figure.

  It can also be a good idea to set a high `:max_overflow` if you are not
  sure what kind of traffic you are going to have at the expense of having to
  start up new processes and connect when required.

  Default: 10

  # Special Note

  In a combined connection your pool size will be doubled to house both TCP
  and UDP - for example if you are using 10 workers, 10 will be TCP and the
  other 10 will be UDP.
  """
  @spec pool_size() :: non_neg_integer()
  def pool_size, do: get_env(:riemannx, :pool_size, 10)

  @doc """
  The strategy determines how workers are placed back in the queue once they
  have finished processing. For more information view the poolboy docs.

  Default: `:fifo`
  """
  @spec strategy() :: :fifo | :lifo
  def strategy, do: get_env(:riemannx, :strategy, :fifo)

  @doc """
  Max overflow is an interesting setting that allows you set an upper limit on
  dynamically created workers that are created when all other workers are busy.

  It can be a good idea to set a high `:max_overflow` if you are not sure what
  kind of traffic you are going to have at the expense of having to start up
  new processes and connect when required.

  Default: 20

  # Special Note

  In a combined connection your overflow will be doubled to house TCP and UDP
  for example if you are using an overflow of 20, your tcp pool will
  have an overflow of 20 and so will the udp pool.
  """
  @spec max_overflow() :: non_neg_integer()
  def max_overflow, do: get_env(:riemannx, :max_overflow, 20)

  @doc """
  The type of connection to use with riemannx - the available options are:

  * `:tcp`
  * `:udp`
  * `:tls`
  * `:combined` (default)

  Combined is the recommended default giving you the best of both worlds, if
  for any reason you can't use both the others are there to fall back on. If
  secure communication is a concern TLS is an option which is a secure TCP-only
  setup.

  REMEMBER: In combined connections your pool sizes/overflow are doubled!

  Default: `:combined`
  """
  @spec type() :: :tcp | :udp | :tls | :combined
  def type, do: get_env(:riemannx, :type, :combined)

  @doc """
  This is more of an internal setting using the type to determine the relative
  module.
  """
  @spec module() :: module()
  def module() do
    case type() do
      :tcp -> Riemannx.Connections.TCP
      :udp -> Riemannx.Connections.UDP
      :tls -> Riemannx.Connections.TLS
      :combined -> Riemannx.Connections.Combined
    end
  end
  @doc """
  The hostname of the server hosting your riemann server.

  Default: "localhost"
  """
  @spec host() :: String.t()
  def host, do: get_env(:riemannx, :host, "localhost")

  @doc """
  The TCP port your riemann server is listening on.

  Default: 5555
  """
  @spec tcp_port() :: :inet.port_number()
  def tcp_port, do: get_env(:riemannx, :tcp_port, 5555)

  @doc """
  The UDP port your riemann server is listening on.

  Default: 5555
  """
  @spec udp_port() :: :inet.port_number()
  def udp_port, do: get_env(:riemannx, :udp_port, 5555)

  @doc """
  Your riemann server will have an upper limit on the allowable size of a UDP
  transmission, it's important you set this correctly as not doing so could
  cause your app to drop stats unnecessarily, especially when using the
  combined connection.

  The default here is set to Riemann's default. This could change at any time
  so it's recommended you double check for the version you are using.

  Default: 16384
  """
  @spec max_udp_size() :: non_neg_integer()
  def max_udp_size, do: get_env(:riemannx, :max_udp_size, 16_384)

  @doc """
  The retry count is how many times riemann will attempt a connection before
  killing the worker (TCP Only). There are 2 choices:

  * A `non_neg_integer()` in seconds
  * `:infinity` to retry until it works

  The default is 5.
  """
  @spec retry_count() :: non_neg_integer() | :infinity
  def retry_count(), do: get_env(:riemannx, :retry_count, 5)

  @doc """
  The retry interval is the amount of time (in seconds) to sleep before
  attempting a reconnect (TCP Only).

  Default: 5
  """
  @spec retry_interval() :: non_neg_integer()
  def retry_interval(), do: get_env(:riemannx, :retry_interval, 5) * 1000

  @doc """
  Retrives SSL options set for a TLS connection. For more information
  on the available options see here: http://erlang.org/doc/man/ssl.html

  In order to use TLS correctly with riemann you need to specify both
  a keyfile and a certfile.
  """
  @spec ssl_options() :: [:ssl.ssl_option()]
  def ssl_options(), do: get_env(:riemannx, :ssl_opts, [])

  @doc """
  Riemannx can inject a host name in your events if you don't supply one before
  sending it - if you don't set this in your config and don't put one in your
  event we will use `:inet.gethostname()` to add one for you.

  Riemannx is smart and will only call `:inet.gethostname()` once and save the
  result so don't worry about it being called for every event!
  """
  @spec events_host() :: binary()
  def events_host() do
    inet_host  = inet_host()
    event_host = get_env(:riemannx, :event_host, nil)
    cond do
      inet_host != nil && event_host == nil ->
        inet_host

      event_host == nil && inet_host == nil ->
        {:ok, host} = :inet.gethostname
        host        = to_string(host)
        put_env(:riemannx, :inet_host, host)
        host

      true ->
        event_host
    end
  end

  ## It's best nobody knows about this, it's internal.
  @spec inet_host() :: binary() | nil
  defp inet_host(), do: get_env(:riemannx, :inet_host, nil)
end

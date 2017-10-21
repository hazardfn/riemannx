defmodule Riemannx.Connection do
  @moduledoc """
  This is the behaviour specification for all connections as well as a generic
  API for communication with them based on the settings given in your config.

  The struct in this module is used across all connection types as much of the
  data is common to all types.
  """
  import Riemannx.Settings

  # ===========================================================================
  # Struct
  # ===========================================================================
  defstruct [
    host: nil,
    tcp_port: nil,
    udp_port: nil,
    max_udp_size: nil,
    ssl_opts: [],
    socket: nil
  ]

  # ===========================================================================
  # Types
  # ===========================================================================
  @type error :: [error: binary(), message: binary()]
  @type encoded_event :: binary()
  @type retry_count :: non_neg_integer() | :infinity
  @type socket :: :gen_udp.socket() | :gen_tcp.socket() | :ssl.sslsocket()
  @type t() :: %__MODULE__{
    host: String.t(),
    tcp_port: :inet.port_number(),
    udp_port: :inet.port_number(),
    max_udp_size: non_neg_integer(),
    ssl_opts: [:ssl.ssl_option()],
    socket: socket()
  }

  # ===========================================================================
  # Callbacks
  # ===========================================================================
  @callback get_worker(e :: encoded_event(), p :: atom()) :: pid() | error()
  @callback send(w :: pid(), e :: encoded_event()) :: :ok | error()
  @callback send_async(w :: pid(), e :: encoded_event()) :: :ok
  @callback release(w :: pid(), e :: encoded_event(), p :: atom()) :: :ok

  # ===========================================================================
  # API
  # ===========================================================================
  @doc """
  Fetches a relevant worker based on your connection type.
  """
  @spec get_worker(encoded_event(), atom()) :: pid() | error()
  def get_worker(e, p \\ :riemannx_pool), do: module().get_worker(e, p)

  @doc """
  Tells the given worker to synchronously process an event.
  """
  @spec send(pid(), encoded_event()) :: :ok | error()
  def send(pid, e), do: module().send(pid, e)

  @doc """
  Tells the given worker to asynchronously process an event.
  """
  @spec send_async(pid(), encoded_event()) :: :ok
  def send_async(pid, e), do: module().send_async(pid, e)

  @doc """
  Tells the given worker to release itself back into the wild.
  """
  @spec release(pid(), encoded_event(), atom()) :: :ok
  def release(pid, e, p \\ :riemannx_pool), do: module().release(pid, e, p)
end

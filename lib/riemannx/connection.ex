defmodule Riemannx.Connection do
  @moduledoc """
  This is the behaviour specification for all connections as well as a generic
  API for communication with them based on the settings given in your config.

  The struct in this module is used across all connection types as much of the
  data is common to all types.
  """
  import Riemannx.Settings
  alias Riemannx.Proto.Msg

  # ===========================================================================
  # Struct
  # ===========================================================================
  defstruct host: nil,
            port: nil,
            options: [],
            to: nil,
            socket: nil

  # ===========================================================================
  # Types
  # ===========================================================================
  @type error :: [error: binary(), message: binary()]
  @type qr :: {:ok, list()}
  @type encoded_event :: binary()
  @type query :: binary()
  @type retry_count :: non_neg_integer() | :infinity
  @type socket :: :gen_udp.socket() | :gen_tcp.socket() | :ssl.sslsocket()
  @type t() :: %__MODULE__{
          host: String.t() | nil,
          port: :inet.port_number() | nil,
          options: list() | nil,
          to: pid() | nil,
          socket: socket() | nil
        }

  # ===========================================================================
  # Callbacks
  # ===========================================================================
  @callback send(e :: encoded_event()) :: :ok | error()
  @callback send_async(e :: encoded_event()) :: :ok
  @callback query(m :: query(), t :: pid()) :: :ok | error()

  # ===========================================================================
  # API
  # ===========================================================================

  @doc """
  Synchronously process an event.
  """
  @spec send(encoded_event()) :: :ok | error()
  def send(e), do: module().send(e)

  @doc """
  Tells the given worker to asynchronously process an event.
  """
  @spec send_async(encoded_event() | Riemannx.events()) :: :ok
  def send_async(e), do: module().send_async(e)

  @doc """
  Query the index of the riemann server, only works with the TLS/TCP/Combined
  setups. UDP is NOT supported.
  """
  @spec query(query(), pid()) :: :ok | error()
  def query(m, to), do: module().query(m, to)

  @doc """
  An acceptable query response.
  """
  def query_ok, do: Msg.encode(Msg.new(ok: true))

  @doc """
  A failed query.
  """
  def query_failed, do: Msg.encode(Msg.new(ok: false))
end

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
  @callback type() :: conn_type() | :combined
  @callback module(conn_type() | :combined) :: module()
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
  @spec pool_name(conn_type()) :: atom()
  def pool_name(t), do: settings_module().pool_name(t)

  @spec pool_size(conn_type()) :: non_neg_integer()
  def pool_size(t), do: settings_module().pool_size(t)

  @spec strategy(conn_type()) :: :fifo | :lifo
  def strategy(t), do: settings_module().strategy(t)

  @spec max_overflow(conn_type()) :: non_neg_integer()
  def max_overflow(t), do: settings_module().max_overflow(t)

  @spec type() :: conn_type() | :combined
  def type, do: settings_module().type()

  @spec module() :: module()
  def module(), do: module(type())

  @spec module(conn_type()) :: module()
  def module(t), do: settings_module().module(t)

  @spec host() :: String.t()
  def host, do: settings_module().host()

  @spec port(conn_type()) :: :inet.port_number()
  def port(t), do: settings_module().port(t)

  @spec max_udp_size() :: non_neg_integer()
  def max_udp_size, do: settings_module().max_udp_size()

  @spec retry_count(conn_type()) :: non_neg_integer() | :infinity
  def retry_count(t), do: settings_module().retry_count(t)

  @spec retry_interval(conn_type()) :: non_neg_integer()
  def retry_interval(t), do: settings_module().retry_interval(t)

  @spec options(conn_type()) :: list()
  def options(t), do: settings_module().options(t)

  @spec events_host() :: binary()
  def events_host(), do: settings_module().events_host()

  @spec priority!(conn_type()) :: priority() | no_return()
  def priority!(t), do: settings_module().priority!(t)

  # ===========================================================================
  # Private
  # ===========================================================================
  @spec settings_module() :: module()
  defp settings_module(), do: get_env(:riemannx, :settings_module, Default)
end

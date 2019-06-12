defmodule Riemannx.Storage do
  @moduledoc """
  A behaviour module for defining storage backends for the client.

  Storage clients are used to siphon data to disk when your riemann server
  is unreachable or all workers are busy for a lengthy period of time. This
  prevents erlang message queue build-up and provides a more stable alternative
  that increases the chances your data will reach it's destination
  during network instability.
  """

  # ===========================================================================
  # Callbacks
  # ===========================================================================
  @callback dump() :: :ok
  @callback write(key :: Settings.conn_type(), data :: term()) ::
              :ok | {:error, atom()}

  # ===========================================================================
  # Public
  # ===========================================================================
  def dump(module), do: module.dump()
  def write(module, key, data), do: module.write(key, data)
end

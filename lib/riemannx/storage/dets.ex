defmodule Riemannx.Storage.Dets do
  @moduledoc """
  A DETS backend for the data siphoning feature.
  """
  @behaviour Riemannx.Storage

  alias __MODULE__
  alias Riemannx.Settings

  use GenServer

  # ===========================================================================
  # Attributes
  # ===========================================================================
  @table_name :riemannx_data

  # ===========================================================================
  # Struct and Types
  # ===========================================================================
  defstruct [:path, :name, :opts]

  @type t :: %Dets{
          path: charlist(),
          name: atom(),
          opts: Keyword.t() | list(atom)
        }

  # ===========================================================================
  # API
  # ===========================================================================
  def dump(), do: GenServer.cast(__MODULE__, :dump)
  def write(key, data), do: GenServer.call(__MODULE__, {:write, key, data})

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================
  @spec start_link(map()) :: {:ok, pid()}
  def start_link(%{path: _, name: _, opts: _} = args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @spec init(map()) :: {:ok, Dets.t()}
  def init(args) do
    path = args.path
    name = args.name
    opts = args.opts
    state = %Dets{path: path, name: name, opts: opts}

    :dets.open_file(name, opts)

    {:ok, state}
  end

  def handle_cast(:dump, _from, state), do: do_dump(state)

  def handle_call({:write, key, data}, _from, state),
    do: do_write(key, data, state)

  # ===========================================================================
  # Supervisor Callbacks
  # ===========================================================================
  def child_spec(args) do
    path = Keyword.fetch!(args, :path)
    opts = Keyword.get(args, :opts, []) ++ [file: path]
    name = Keyword.get(args, :name, @table_name)
    args = %{path: path, name: name, opts: opts}

    %{id: __MODULE__, start: {__MODULE__, :start_link, [args]}}
  end

  # ===========================================================================
  # Private
  # ===========================================================================
  defp do_dump(state) do
    :dets.traverse(state.name, fn {k, v} = x ->
      {:continue, [Settings.module(k).send(v) | x]}
    end)
  end
end

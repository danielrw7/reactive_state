defmodule Reactive.ETS do
  @moduledoc """
  Module to manage ETS table operations
  """

  @doc "Start the necessary ETS tables"
  def ensure_started do
    ensure_started(Reactive.ETS.Method)
    ensure_started(Reactive.ETS.Process)
    ensure_started(Reactive.ETS.ProcessOpts, [:bag, :public])
    ensure_started(Reactive.ETS.Counter, [:ordered_set, :public])
  end

  @doc "Start an ETS table"
  def ensure_started(name, opts \\ [:set, :public]) do
    id =
      case :ets.whereis(name) do
        :undefined -> :ets.new(name, [:named_table | opts])
        id -> id
      end

    {:ok, id}
  end

  @doc false
  def get(name, key, default \\ nil) do
    case :ets.lookup(name, key) do
      [{_, value}] -> value
      [] -> default
    end
  end

  @doc false
  def get_all(name, key) do
    :ets.lookup(name, key)
  end

  @doc false
  def get_all(name) do
    :ets.tab2list(name)
  end

  @doc false
  def set(name, key, value) do
    :ets.insert(name, {key, value})
  end

  @doc false
  def counter(name, key, value \\ 1, default \\ 0) do
    :ets.update_counter(name, key, value, {key, default})
  end

  @doc "Empty ETS tables"
  def empty do
    empty(Reactive.ETS.Method)
    empty(Reactive.ETS.Process)
    empty(Reactive.ETS.ProcessOpts)
    empty(Reactive.ETS.Counter)
  end

  @doc "Empty ETS table"
  def empty(name) do
    case :ets.whereis(name) do
      :undefined -> nil
      _ -> :ets.delete_all_objects(name)
    end
  end

  @doc "Reset ETS table"
  def reset(name) do
    case :ets.whereis(name) do
      :undefined ->
        ensure_started(name)

      _ ->
        empty(name)
        ensure_started(name)
    end
  end
end

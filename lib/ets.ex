defmodule Reactive.ETS do
  def ensure_started do
    ensure_started(Reactive.ETS.Method)
    ensure_started(Reactive.ETS.Process)
    ensure_started(Reactive.ETS.Immediate, [:bag, :public])
  end

  def ensure_started(name, opts \\ [:set, :public]) do
    id =
      case :ets.whereis(name) do
        :undefined -> :ets.new(name, [:named_table | opts])
        id -> id
      end

    {:ok, id}
  end

  def get(name, key) do
    case :ets.lookup(name, key) do
      [{_, value}] -> value
      [] -> nil
    end
  end

  def get_all(name, key) do
    :ets.lookup(name, key)
  end

  def set(name, key, value) do
    :ets.insert(name, {key, value})
  end
end

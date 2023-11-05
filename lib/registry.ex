defmodule Reactive.Registry do
  def init do
    pid =
      case Registry.start_link(keys: :unique, name: Reactive.Registry) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    {:ok, pid}
  end

  def get(key) do
    case Registry.lookup(Reactive.Registry, key) do
      [] -> nil
      pid -> pid
    end
  end

  def via(key) do
    {:via, Registry, {Reactive.Registry, key}}
  end

  def supervisor do
    case get("supervisor") do
      nil -> supervisor_create()
      [{pid, _}] -> pid
    end
  end

  def supervisor_create do
    {:ok, pid} = Reactive.Supervisor.start_link(name: via("supervisor"))
    pid
  end
end

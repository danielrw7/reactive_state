defmodule Reactive.Supervisor do
  @moduledoc """
  Default DynamicSupervisor to manage task creation and garbage collection.
  """

  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Start the supervisor if needed (not recommended)"
  def ensure_started do
    {exists, pid} =
      case Process.whereis(Reactive.Supervisor) do
        nil -> {false, nil}
        pid -> {Process.alive?(pid), pid}
      end

    case exists do
      false -> Supervisor.start_link([Reactive.Supervisor], strategy: :one_for_one)
      _ -> {:ok, pid}
    end
  end

  @doc """
  Garbage collect processes for a supervisor (Reactive.Supervisor by default)

  Options:
  - name: [pid or alias] (default: `Reactive.Supervisor`)
  - strategy: :counter (default `:counter`)
  - count: [integer] (default `nil`)
  - random: [boolean] (default `false`)

  Example:

      iex> Reactive.Supervisor.ensure_started()
      iex> ref = Ref.new(0)
      iex> Reactive.Supervisor.gc()
      iex> nil == Reactive.resolve_process(ref)

  Reactive processes can be protected with the `gc` option:

      iex> use Reactive
      iex> Reactive.Supervisor.ensure_started()
      iex> ref = Ref.new(0, gc: false)
      iex> Reactive.Supervisor.gc()
      iex> ^ref = Reactive.resolve_process(ref)

      iex> use Reactive
      iex> Reactive.Supervisor.ensure_started()
      iex> ref = reactive gc: false do
      ...>    # some expensive computation
      ...> end
      iex> Reactive.Supervisor.gc()
      iex> ^ref = Reactive.resolve_process(ref)
  """
  def gc(opts \\ []) do
    name = Keyword.get(opts, :name, Reactive.Supervisor)
    count = opts[:count]
    selection = opts[:random]
    strategy = Keyword.get(opts, :strategy, :counter)

    no_gc_protect =
      Reactive.ETS.get_all(Reactive.ETS.ProcessOpts, :no_gc)
      |> Enum.map(&Reactive.resolve_process(&1 |> elem(1)))
      |> MapSet.new()

    protect =
      case opts[:protect] do
        nil -> MapSet.new()
        [] -> MapSet.new()
        pids -> pids |> Enum.map(&Reactive.resolve_process/1) |> MapSet.new()
      end
      |> MapSet.union(no_gc_protect)

    children = DynamicSupervisor.which_children(name)

    {children, protect} =
      case strategy do
        :counter ->
          {
            children,
            Reactive.ETS.get_all(Reactive.ETS.Counter)
            |> Enum.map(&elem(&1, 0))
            |> Enum.map(&Reactive.resolve_process/1)
            |> MapSet.new()
            |> MapSet.union(protect)
          }

        _ ->
          {
            children,
            protect
          }
      end

    children =
      case protect do
        nil -> children
        map when map_size(map) == 0 -> children
        _ -> children |> Stream.filter(&(!MapSet.member?(protect, &1 |> elem(1))))
      end

    children =
      case {count, selection} do
        {nil, _} -> children
        {count, :random} -> Enum.take_random(children, count)
        {count, _} -> Enum.take(children, count)
      end

    for {_, child, _, _} <- children do
      DynamicSupervisor.terminate_child(Reactive.Supervisor, child)
    end

    if opts[:reset] != false do
      Reactive.ETS.reset(Reactive.ETS.Counter)
    end
  end

  @doc """
  Trigger computations for any stale reactive processes who have the option `proactive: true`

  Example:

      iex> use Reactive
      iex> Reactive.Supervisor.ensure_started()
      iex> num = Ref.new(0)
      iex> ref =
      ...>   reactive proactive: true do
      ...>     get(num) + 1
      ...>   end
      iex> Reactive.get_cached(ref)
      1
      iex> Ref.set(num, 1)
      iex> Reactive.Supervisor.trigger_proactive()
      iex> Reactive.get_cached(ref)
      2
  """
  def trigger_proactive(opts \\ []) do
    exclude = opts[:exclude]

    processes =
      Keyword.get(opts, :name, Reactive.ETS.ProcessOpts)
      |> Reactive.ETS.get_all(:proactive)
      |> Stream.map(&Reactive.resolve_process(&1 |> elem(1), create: true))
      |> Enum.filter(& &1)

    case opts[:exclude] do
      nil -> processes
      _ -> processes |> Enum.filter(&(!MapSet.member?(exclude, &1)))
    end
    |> trigger_proactive_call(Keyword.get(opts, :times, 1))
  end

  @doc false
  def trigger_proactive_call(processes, times \\ 1)

  def trigger_proactive_call(_processes, 0), do: false

  def trigger_proactive_call(processes, times) do
    any_changed =
      for pid <- processes do
        Reactive.compute_if_needed(pid)
      end
      |> Enum.filter(&(&1 == :changed))
      |> Enum.any?()

    if any_changed do
      trigger_proactive_call(processes, times - 1)
      any_changed
    end
  end
end

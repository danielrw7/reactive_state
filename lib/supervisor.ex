defmodule Reactive.Supervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def ensure_started do
    case Process.whereis(Reactive.Supervisor) do
      nil -> Supervisor.start_link([Reactive.Supervisor], strategy: :one_for_one)
      pid -> {:ok, pid}
    end
  end

  def gc(opts \\ []) do
    name = Keyword.get(opts, :name, Reactive.Supervisor)
    count = Keyword.get(opts, :count)
    strategy = Keyword.get(opts, :strategy, :usage)

    protect =
      case opts[:protect] do
        nil -> nil
        [] -> nil
        pids -> pids |> Enum.map(&Reactive.resolve_process/1) |> MapSet.new()
      end

    children = DynamicSupervisor.which_children(name)

    children =
      case protect do
        nil -> children
        map when map_size(map) == 0 -> children
        _ -> children |> Stream.filter(&(!MapSet.member?(protect, &1 |> elem(1))))
      end

    children =
      case {count, strategy} do
        {nil, _} -> children
        {count, true} -> Enum.take_random(children, count)
        {count, _} -> Enum.take(children, count)
      end

    for {_, child, _, _} <- children do
      if Reactive.can_gc?(child) do
        DynamicSupervisor.terminate_child(Reactive.Supervisor, child)
      end
    end
  end

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

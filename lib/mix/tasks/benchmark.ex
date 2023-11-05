defmodule Benchmark do
  @moduledoc false

  defmacro measure(label, ast) do
    # https://stackoverflow.com/a/29674651
    quote do
      method = fn -> unquote(ast) end

      {time, [do: res]} = :timer.tc(method)

      IO.puts("#{unquote(label)} took #{Kernel./(time, 1_000_000)}s")

      res
    end
  end
end

defmodule Mix.Tasks.Benchmark do
  @moduledoc "Printed when the user requests `mix benchmark`"
  @shortdoc "Runs benchmarks"

  use Mix.Task
  use Reactive

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [count: :integer, help: :boolean],
        aliases: [c: :count, h: :help]
      )

    default_count = 10_000

    cond do
      Keyword.get(opts, :help, false) ->
        """
        Options:
          -h, --help
          -c, --count [int] (default: #{default_count})
        """
        |> String.trim()
        |> IO.puts()

      true ->
        Keyword.get(opts, :count, default_count)
        |> benchmark()
    end
  end

  def recursive_reactive(pids, 0) do
    pids
  end

  def recursive_reactive(pids, i) do
    [last | _] = pids

    next =
      reactive name: "ref_#{i}" do
        get(last) + 1
      end

    recursive_reactive([next | pids], i - 1)
  end

  def benchmark(count) do
    require Benchmark

    Benchmark.measure "total" do
      {:ok, _} = Reactive.Supervisor.ensure_started()
      # {:ok, _} = Reactive.Supervisor.ensure_started()
      first = Ref.new(1, name: "ref_#{count}")

      [last | rest] =
        Benchmark.measure "create" do
          recursive_reactive([first], count - 1)
        end

      Benchmark.measure "compute last" do
        true = Ref.get(last) == count
      end

      Benchmark.measure "recompute all" do
        Ref.set(first, 2)
        true = Ref.get(last) == count + 1
      end

      Benchmark.measure "gc" do
        rest
        |> Enum.at(1)
        |> Ref.set_fn(&(&1 + 1))

        Benchmark.measure "gc.call" do
          Reactive.Supervisor.gc()
        end

        DynamicSupervisor.count_children(Reactive.Supervisor) |> dbg()
      end

      Benchmark.measure "compute last again" do
        true = Ref.get(last) == count + 2
        DynamicSupervisor.count_children(Reactive.Supervisor) |> dbg()
      end
    end
  end
end

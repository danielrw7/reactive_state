defmodule Benchmark do
  @moduledoc false

  defmacro measure(ast) do
    # https://stackoverflow.com/a/29674651
    quote do
      fn -> unquote(ast) end
      |> :timer.tc()
      |> elem(0)
      |> Kernel./(1_000_000)
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
      reactive do
        get(last) + 1
      end

    recursive_reactive([next | pids], i - 1)
  end

  def benchmark(count) do
    require Benchmark

    seconds =
      Benchmark.measure do
        first = Ref.new(0)

        [last | _] = recursive_reactive([first], count)

        true = Ref.get(last) == count
        Ref.set(first, 1)
        true = Ref.get(last) == count + 1
      end

    IO.puts("took #{seconds}s for #{count} recursively referenced cells")
  end
end

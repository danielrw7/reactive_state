defmodule ReactiveTest do
  use ExUnit.Case
  require Benchmark
  use Reactive

  setup_all do
    Reactive.Supervisor.ensure_started()
    :ok
  end

  setup do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(Reactive.Supervisor) do
      DynamicSupervisor.terminate_child(Reactive.Supervisor, pid)
    end

    :ok
  end

  doctest Reactive
  doctest Reactive.Ref

  test "invalidate" do
    use Reactive
    first = Ref.new(0)
    second = Ref.new(0)
    branch = Ref.new(true)

    computed =
      reactive do
        if get(branch) do
          get(first)
        else
          get(second)
        end
      end

    Reactive.get(computed)
    assert :stale != Reactive.get_cached(computed)
    Ref.set(first, 1)
    assert :stale == Reactive.get_cached(computed)

    Reactive.get(computed)
    Ref.set(branch, false)
    assert :stale == Reactive.get_cached(computed)
    Reactive.get(computed)
    assert :stale != Reactive.get_cached(computed)
    Ref.set(first, 2)
    assert :stale != Reactive.get_cached(computed)

    Reactive.get(computed)
    Ref.set(second, 1)
    assert :stale == Reactive.get_cached(computed)
  end

  test "restart" do
    use Reactive
    ref = Ref.new(0)
    DynamicSupervisor.terminate_child(Reactive.Supervisor, ref)
    val = Ref.get(ref)
    assert 0 == val
  end

  test "resolve_process" do
    use Reactive
    ref = Ref.new(0)
    assert ref == Reactive.resolve_process(ref)
    DynamicSupervisor.terminate_child(Reactive.Supervisor, ref)
    assert !alive?(ref)
    assert Reactive.resolve_process(ref, create: true) |> Process.alive?()
    assert 0 == Ref.get(ref)
  end

  test "gc" do
    use Reactive
    first = Ref.new(0, name: :first)
    second = Ref.new(1, name: :second)
    branch = Ref.new(true, name: :branch)

    computed =
      reactive name: :computed do
        if get(branch) do
          get(first)
        else
          get(second)
        end
      end

    Reactive.Supervisor.gc()
    assert !alive?(first)
    assert !alive?(second)
    assert !alive?(branch)
    assert !alive?(computed)

    assert 0 == Reactive.get(computed)
    assert alive?(first)
    assert !alive?(second)
    assert alive?(branch)
    assert alive?(computed)

    Ref.set(branch, false)
    assert 1 == Reactive.get(computed)
    assert alive?(first)
    assert alive?(second)
    assert alive?(branch)
    assert alive?(computed)

    Reactive.Supervisor.gc(protect: [computed])
    assert !alive?(first)
    assert alive?(second)
    assert alive?(branch)
    assert alive?(computed)

    ref = Ref.new(0, gc: false)
    assert alive?(ref)
    Reactive.Supervisor.gc()
    assert alive?(ref)

    ref =
      reactive gc: false do
        0
      end

    assert alive?(ref)
    Reactive.Supervisor.gc()
    assert alive?(ref)
  end

  test "immediate" do
    use Reactive
    num = Ref.new(0)

    ref =
      reactive immediate: true do
        get(num) + 1
      end

    assert 1 == Reactive.get_cached(ref)

    Ref.set(num, 1)
    Reactive.Supervisor.trigger_immediate()
    assert 2 == Reactive.get_cached(ref)
  end

  def alive?(pid) do
    Reactive.resolve_process(pid) != nil
  end
end

defmodule ReactiveTest do
  use ExUnit.Case
  require Benchmark
  use Reactive

  setup_all do
    Reactive.Supervisor.ensure_started()
    :ok
  end

  setup do
    # Reactive.ETS.empty({nil, :all})

    # for {_, pid, _, _} <- DynamicSupervisor.which_children(Reactive.Supervisor) do
    #   DynamicSupervisor.terminate_child(Reactive.Supervisor, pid)
    # end

    :ok
  end

  doctest Reactive
  doctest Reactive.Ref
  doctest Reactive.Supervisor
  doctest Reactive.ETS

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

    assert 0 == Reactive.get(computed)
    assert 0 == Reactive.get_cached(computed)
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
    first = Ref.new(0)
    second = Ref.new(1)
    branch = Ref.new(true)

    computed =
      reactive do
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

    Reactive.Supervisor.gc()
    assert alive?(first)
    assert !alive?(second)
    assert alive?(branch)
    assert alive?(computed)

    Reactive.Supervisor.gc(protect: [computed])
    assert !alive?(first)
    assert !alive?(second)
    assert !alive?(branch)
    assert alive?(computed)

    # protect process
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

    # reactivity still works
    ref = Ref.new(0)

    computed =
      reactive gc: false do
        get(ref) + 1
      end

    Reactive.get(computed)
    Reactive.Supervisor.gc()
    Reactive.Supervisor.gc()
    assert !alive?(ref)
    assert alive?(computed)

    Ref.set(ref, 1)
    assert :stale == Reactive.get_cached(computed)
  end

  test "proactive" do
    use Reactive
    num = Ref.new(0)
    num2 = Ref.new(1)

    ref =
      reactive proactive: true do
        get(num) + get(num2)
      end

    assert 1 == Reactive.get_cached(ref)

    Ref.set(num, 1)
    assert :stale == Reactive.get_cached(ref)

    Reactive.Supervisor.trigger_proactive()
    assert 2 == Reactive.get_cached(ref)
  end

  test "counters" do
    x = Ref.new(0)
    assert nil == Reactive.ETS.get({nil, Counter}, x)
    Ref.get(x)
    assert 1 == Reactive.ETS.get({nil, Counter}, x)
    Ref.get(x)
    assert 2 == Reactive.ETS.get({nil, Counter}, x)

    # get_cached does not update counter
    Reactive.get_cached(x)
    assert 2 == Reactive.ETS.get({nil, Counter}, x)

    Reactive.ETS.reset({nil, Counter})
    assert nil == Reactive.ETS.get({nil, Counter}, x)
  end

  def alive?(pid) do
    Reactive.resolve_process(pid) != nil
  end
end

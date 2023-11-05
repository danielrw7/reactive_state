defmodule ReactiveTest do
  use ExUnit.Case
  doctest Reactive
  use Reactive
  doctest Reactive.Ref

  test "invalidate" do
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
end

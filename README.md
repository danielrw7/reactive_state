# Reactive State - Elixir

Elixir library to manage reactive state by using GenServer processes to manage each piece of state and its relationships to other reactive processes

> [!WARNING]  
> This library is a work in progress and is not production ready.

## Installation

The package can be installed by adding `reactive_state` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:reactive_state, "~> 0.2.4"}
  ]
end
```

## Documentation

[Full API Documentation can be found on HexDocs](https://hexdocs.pm/reactive_state/)

## Examples

### Reactive Block

To automatically import the `reactive/1` and `reactive/2` macros, you can use `use Reactive` which is the equivalent of:

```elixir
import Reactive, only: [reactive: 1, reactive: 2]
alias Reactive.Ref
```

Example usage:

```elixir
use Reactive
ref = reactive(do: 2)
ref_squared = reactive do
  get(ref) ** 2
end
Reactive.get(ref_squared)
# 4
Ref.set(ref, 3)
Reactive.get(ref_squared)
# 9
```

To set options at the module level, you can pass options, for example:

```elixir
defmodule ReactiveExample do
  use Reactive, reactive: :reactive_protected, ref: :ref_protected, opts: [gc: false]

  def run do
    value = ref_protected(0)
    computed = reactive_protected do
      get(value) + 1
    end
    {Ref.get(value), Ref.get(computed)}
  end
end

ReactiveExample.run()
# {0, 1}
```

### Working with data directly with `Reactive.Ref`
```elixir
alias Reactive.Ref
ref = Ref.new(0) #PID<0.204.0>
Ref.get(ref) # or Ref.get(ref)
# 0
Ref.set(ref, 1)
# :ok
Ref.get(ref)
# 1
```

### Supervisor

By default, new reactive processes will be linked to the current process.
To override this behavior, pass the `supervisor` keyword arg with the name of your `DynamicSupervisor` during process creation:

```elixir
value = Ref.new(0, supervisor: MyApp.Supervisor)
computed = reactive supervisor: MyApp.Supervisor do
  get(value) + 1
end
```

You can also pass default options like this:

```elixir
use Reactive, ref: :ref, opts: [supervisor: MyApp.Supervisor]
...
value = ref(0)
computed = reactive do
  get(value) + 1
end
```

### Process Restarting

If a reactive process has been killed for any reason, it will be restarted upon a `Reactive.get` or `Ref.get` call:

```elixir
use Reactive
Reactive.Supervisor.ensure_started()
ref = Ref.new(0)
DynamicSupervisor.terminate_child(Reactive.Supervisor, ref)
Ref.get(ref)
# 0
```

### Garbage Collection

The default garbage collection strategy is to kill any processes that were not accessed through
a `Reactive.get` or `Ref.get` call between GC calls:

```elixir
Reactive.Supervisor.ensure_started()
ref = Ref.new(0)
Reactive.Supervisor.gc()
nil == Reactive.resolve_process(ref)
```

Reactive processes can be protected with the `gc` option:

```elixir
use Reactive
Reactive.Supervisor.ensure_started()

ref = Ref.new(0, gc: false)
Reactive.Supervisor.gc()
^ref = Reactive.resolve_process(ref)

ref = reactive gc: false do
   # some expensive computation
end
Reactive.Supervisor.gc()
^ref = Reactive.resolve_process(ref)
```

## Proactive Process

Proactive reactive processes will not trigger immediately after a dependency changes; they must triggered with a call to `Reactive.Supervisor.trigger_proactive`

```elixir
use Reactive
Reactive.Supervisor.ensure_started()

num = Ref.new(0)
ref =
  reactive proactive: true do
    get(num) + 1
  end

Reactive.get_cached(ref)
# 1

Ref.set(num, 1)
Reactive.Supervisor.trigger_proactive()
Reactive.get_cached(ref)
# 2
```

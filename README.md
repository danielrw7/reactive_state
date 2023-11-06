# Reactive State - Elixir

Elixir library to manage reactive state by using GenServer processes to manage each piece of state and its relationships to other reactive processes

## Installation

The package can be installed by adding `reactive_state` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:reactive_state, "~> 0.2.1"}
  ]
end
```

## Documentation

[Full API Documentation can be found on HexDocs](https://hexdocs.pm/reactive_state/)

## Examples

Module to manage reactive state by using GenServer processes ("reactive process" from here on) to manage each piece of state and its relationships to other reactive processes.

### Working with data directly with `Reactive.Ref`

```elixir
ref = Ref.new(0) #PID<0.204.0>
Ref.get(ref) # or Ref.get(ref)
# 0
Ref.set(ref, 1)
# :ok
Ref.get(ref)
# 1
```

### Reactive Block

```elixir
use Reactive
ref = Ref.new(2)
ref_squared = reactive do
  get(ref) ** 2
end

Reactive.get(ref_squared)
# 4

Ref.set(ref, 3)
Reactive.get(ref_squared)
# 9
```

#### Conditional Branches

```elixir
use Reactive
if_false = Ref.new(1)
if_true = Ref.new(2)
toggle = Ref.new(false)
computed = reactive do
  if get(toggle) do
    get(if_true)
  else
    get(if_false)
  end
end

Reactive.get(computed)
# 1
Ref.set(toggle, true)
# :ok
Reactive.get(computed)
# 2

# Now, updating `if_false` will not require a recomputation
Ref.set(if_false, 0)
# :ok
Reactive.get_cached(computed)
# 2

# Updating `if_true` will require a recomputation
Ref.set(if_true, 3)
# :ok
Reactive.get_cached(computed)
# :stale
Reactive.get(computed)
# 3
```

### Supervisor

By default, new reactive processes will be started under the DynamicSupervisor `Reactive.Supervisor`,
if that supervisor exists. If not, it will be created under the current process.

To override this behavior, pass the `supervisor` keyword arg during process creation:

```elixir
value = Ref.new(0, supervisor: MyApp.Supervisor)
ref = reactive supervisor: MyApp.Supervisor do
  get(value) + 1
end
```

These examples include a method which automatically starts the supervisor for you (`Reactive.Supervisor.ensure_started`),
but you should set it up in your own supervision tree.

### Process Restarting

If a reactive process has been killed for any reason, it will be restarted upon a `Reactive.get` or `Ref.get` call:

```elixir
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

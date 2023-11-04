# Reactive State - Elixir

Elixir library to manage reactive state by using GenServer processes to manage each piece of state and its relationships to other reactive processes

## Installation

The package can be installed by adding `reactive_state` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:reactive_state, "~> 0.1.0"}
  ]
end
```

## Documentation

[Full API Documentation can be found on HexDocs](https://hexdocs.pm/reactive_state/)

## Examples

### Working with data directly with `Reactive.Ref`

```elixir
use Reactive
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
...>   get(ref) ** 2
...> end
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
```

Now, updating `if_false` will not require a recomputation:

```elixir
iex> Ref.set(if_false, 0)
:ok
iex> Reactive.get_cached(computed)
2
```

Updating `if_true` will now require a recomputation:

```elixir
iex> Ref.set(if_true, 3)
:ok
iex> Reactive.get_cached(computed)
:stale
iex> Reactive.get(computed)
3
```

defmodule Reactive do
  @moduledoc """
  Module to manage reactive state by using GenServer processes ("reactive process" from here on) to manage each piece of state and its relationships to other reactive processes

  ## Examples

  ### Working with data directly with `Reactive.Ref`

      iex> use Reactive
      iex> ref = Ref.new(0) #PID<0.204.0>
      iex> Ref.get(ref) # or Ref.get(ref)
      0
      iex> Ref.set(ref, 1)
      :ok
      iex> Ref.get(ref)
      1

  ### Reactive Block

      iex> use Reactive
      iex> ref = Ref.new(2)
      iex> ref_squared = reactive do
      ...>   get(ref) ** 2
      ...> end
      iex> Reactive.get(ref_squared)
      4
      iex> Ref.set(ref, 3)
      iex> Reactive.get(ref_squared)
      9

  #### Conditional Branches

      iex> use Reactive
      iex> if_false = Ref.new(1)
      iex> if_true = Ref.new(2)
      iex> toggle = Ref.new(false)
      iex> computed = reactive do
      ...>   if get(toggle) do
      ...>     get(if_true)
      ...>   else
      ...>     get(if_false)
      ...>   end
      ...> end
      iex> Reactive.get(computed)
      1
      iex> Ref.set(toggle, true)
      :ok
      iex> Reactive.get(computed)
      2
      iex> # Now, updating `if_false` will not require a recomputation
      iex> Ref.set(if_false, 0)
      :ok
      iex> Reactive.get_cached(computed)
      2
      iex> # Updating `if_true` will require a recomputation
      iex> Ref.set(if_true, 3)
      :ok
      iex> Reactive.get_cached(computed)
      :stale
      iex> Reactive.get(computed)
      3
  """

  use GenServer

  defmacro __using__(_opts) do
    quote do
      import Reactive, only: [reactive: 1]
      alias Reactive.Ref
    end
  end

  @doc false
  def start_link(method) when is_function(method) do
    GenServer.start_link(__MODULE__, method)
  end

  @doc """
  Create a reactive process using a method

      iex> use Reactive
      iex> ref = Ref.new(2)
      iex> ref_squared = Reactive.new(fn call_id ->
      ...>   Reactive.get(ref, call_id) ** 2
      ...> end)
      iex> Reactive.get(ref_squared)
      4
  """
  def new(method) when is_function(method) do
    {:ok, pid} = Reactive.start_link(method)
    pid
  end

  @doc """
  Syntatic sugar for creating reactive blocks

      iex> use Reactive
      iex> ref = Ref.new(2)
      iex> ref_squared = reactive do
      ...>   get(ref) ** 2
      ...> end #PID<0.204.0>
      iex> Reactive.get(ref_squared)
      4
      iex> Ref.set(ref, 3)
      iex> Reactive.get(ref_squared)
      9

  Using the `reactive` macro in this way is roughly equivalent to:

      iex> use Reactive
      iex> ref = Ref.new(2)
      iex> ref_squared = Reactive.new(fn call_id ->
      ...>   Reactive.get(ref, call_id) ** 2
      ...> end)
      iex> Reactive.get(ref_squared)
      4
      iex> Ref.set(ref, 3)
      iex> Reactive.get(ref_squared)
      9
  """
  defmacro reactive(ast) do
    quote do
      Reactive.new(fn call_id ->
        var!(get) = fn ref -> Reactive.Ref.get(ref, call_id) end
        [do: value] = unquote(Reactive.Macro.traverse(ast))
        var!(get) # suppress unused variable warning
        value
      end)
    end
  end

  @doc """
  Replace a reactive process's computation method

      iex> use Reactive
      iex> ref = reactive do
      ...>   0
      ...> end
      iex> Reactive.get(ref)
      0
      iex> Reactive.set(ref, fn _ -> 1 end)
      :ok
      iex> Reactive.get(ref)
      1
  """
  def set(pid, method) when is_function(method) do
    GenServer.call(pid, {:set, method})
  end

  @doc """
  Retrieve the state of a reactive process

  ## Example

      iex> ref = Reactive.new(fn _ -> 0 end)
      iex> Reactive.get(ref)
      0
  """
  def get(pid) do
    GenServer.call(pid, {:get_dry})
  end

  @doc """
  Retrieve the state of a reactive process, and register the current process as dependent of that process, with the call ID of the current process.
  You should use the `Reactive.reactive` macro to manage reactive relationships instead

  ## Example

      iex> use Reactive
      iex> ref = reactive do
      ...>   0
      ...> end
      iex> Reactive.get(ref)
      0
  """
  def get(pid, call_id) when is_integer(call_id) do
    GenServer.call(pid, {:get, call_id})
  end

  @doc """
  Retrieve the cached state of a reactive process, or :stale if it has not been computed or is stale

  ## Example

      iex> use Reactive
      iex> ref = reactive do
      ...>   0
      ...> end
      iex> Reactive.get_cached(ref)
      :stale
      iex> Reactive.get(ref)
      0
      iex> Reactive.get_cached(ref)
      0
  """
  def get_cached(pid) do
    GenServer.call(pid, {:get_cached})
  end

  @doc false
  def stale({pid, call_id}) do
    if Process.alive?(pid) do
      GenServer.call(pid, {:stale, call_id})
    else
      :ok
    end
  end

  @doc false
  @impl true
  def init(method) when is_function(method) do
    {:ok, {method, 0, :stale, %{}}}
  end

  @doc false
  @impl true
  def handle_call({:set, method}, _, {_method, call_id, _state, listeners})
      when is_function(method) do
    mark_listeners_stale(listeners)
    {:reply, :ok, {method, call_id + 1, :stale, %{}}}
  end

  @doc false
  @impl true
  def handle_call(
        {:stale, expected_call_id},
        _,
        {method, call_id, _state, listeners} = full_state
      ) do
    if expected_call_id == call_id do
      mark_listeners_stale(listeners)

      {
        :reply,
        :ok,
        {method, call_id + 1, :stale, %{}}
      }
    else
      {
        :reply,
        :ok,
        full_state
      }
    end
  end

  @doc false
  @impl true
  def handle_call({:get, dependent_call_id}, {from, _}, {method, call_id, state, listeners}) do
    state = compute(method, call_id, state)

    {:reply, state, {method, call_id, state, listeners |> Map.put(from, dependent_call_id)}}
  end

  @doc false
  @impl true
  def handle_call({:get_dry}, _, {method, call_id, state, listeners}) do
    state = compute(method, call_id, state)

    {:reply, state, {method, call_id, state, listeners}}
  end

  @doc false
  @impl true
  def handle_call({:get_cached}, _, {_method, _call_id, state, _listeners} = full_state) do
    {:reply, state, full_state}
  end

  @doc false
  defp compute(method, call_id, state) do
    case state do
      :stale -> method.(call_id)
      _ -> state
    end
  end

  @doc false
  defp mark_listeners_stale(listeners) do
    for listener <- listeners do
      :ok = stale(listener)
    end
  end
end

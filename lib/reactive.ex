defmodule Reactive do
  @moduledoc """
  Module to manage reactive state by using GenServer processes ("reactive process" from here on) to manage each piece of state and its relationships to other reactive processes

  ## Installation

  The package can be installed by adding `reactive_state` to your list of dependencies in `mix.exs`:

  ```elixir
  def deps do
    [
      {:reactive_state, "~> 0.2.0"}
    ]
  end
  ```

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

  defstruct [
    :method,
    :name,
    :opts,
    :call_id,
    :state,
    :listeners
  ]

  use GenServer

  defmacro __using__(_opts) do
    quote do
      import Reactive, only: [reactive: 1, reactive: 2]
      alias Reactive.Ref
    end
  end

  @doc false
  def start_link({method, name, _opts} = args) when is_function(method) do
    with {:ok, pid} <- GenServer.start_link(__MODULE__, args) do
      name = name || pid

      Reactive.ETS.set(Reactive.ETS.Method, name, method)

      if name != pid do
        Reactive.ETS.set(Reactive.ETS.Process, name, pid)
      end

      {:ok, pid}
    end
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
  def new(method, opts \\ []) when is_function(method) do
    name = opts[:name]

    supervisor_pid =
      case Keyword.get(opts, :supervisor, Reactive.Supervisor) do
        false -> nil
        name -> Process.whereis(name)
      end

    opts =
      opts
      |> Keyword.delete(:name)
      |> Keyword.delete(:supervisor)

    {:ok, pid} =
      case supervisor_pid do
        nil ->
          Reactive.start_link({method, name, opts})

        _ ->
          DynamicSupervisor.start_child(
            supervisor_pid,
            {Reactive, {method, name, opts}}
          )
      end

    name || pid
  end

  def resolve_process(pid, opts \\ []) do
    name = pid

    {check, pid} =
      case is_pid(pid) && Process.alive?(pid) do
        true -> {false, pid}
        false -> {true, Reactive.ETS.get(Reactive.ETS.Process, pid)}
      end

    pid =
      case {check, pid} do
        {false, pid} -> pid
        {true, nil} -> nil
        {true, pid} -> if Process.alive?(pid), do: pid
      end

    pid =
      case {pid, opts[:create]} do
        {nil, true} ->
          Reactive.new(Reactive.ETS.get(Reactive.ETS.Method, name),
            name: name
          )
          |> Reactive.resolve_process()

        {pid, _} ->
          pid
      end

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
  defmacro reactive(opts) do
    Reactive.reactive_ast(opts)
  end

  defmacro reactive(opts, do: ast) do
    opts
    |> Keyword.put(:do, ast)
    |> Reactive.reactive_ast()
  end

  def reactive_ast(opts) do
    {ast, opts} = Keyword.pop(opts, :do)

    quote do
      Reactive.new(
        fn call_id ->
          var!(get) = fn ref -> Reactive.Ref.get(ref, call_id) end
          value = unquote(Reactive.Macro.traverse(ast))
          # suppress unused variable warning
          var!(get)
          value
        end,
        unquote(opts)
      )
    end
  end

  @doc false
  def call(pid, args) do
    pid
    |> Reactive.resolve_process(create: true)
    |> GenServer.call(args)
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
    case Reactive.resolve_process(pid) do
      nil -> Reactive.new(method, name: pid)
      resolved_pid -> GenServer.call(resolved_pid, {:set, method})
    end
  end

  @doc """
  Retrieve the state of a reactive process

  ## Example

      iex> ref = Reactive.new(fn _ -> 0 end)
      iex> Reactive.get(ref)
      0
  """
  def get(pid) do
    Reactive.call(pid, {:get_dry})
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
    Reactive.call(pid, {:get, call_id})
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
    case Reactive.resolve_process(pid) do
      nil -> :stale
      pid -> GenServer.call(pid, {:get_cached})
    end
  end

  @doc false
  def stale({pid, call_id}) do
    case Reactive.resolve_process(pid) do
      nil -> :ok
      pid -> GenServer.call(pid, {:stale, call_id})
    end
  end

  @doc false
  def get_call_id(pid) do
    case Reactive.resolve_process(pid) do
      nil -> :dead
      pid -> GenServer.call(pid, {:get_call_id})
    end
  end

  @doc false
  def compute_if_needed(pid) do
    case Reactive.resolve_process(pid) do
      nil -> :dead
      pid -> GenServer.call(pid, {:compute_if_needed})
    end
  end

  @doc false
  def can_gc?(pid) do
    case Reactive.resolve_process(pid) do
      nil -> false
      pid -> GenServer.call(pid, {:can_gc?})
    end
  end

  @doc false
  @impl true
  def init({method, name, opts}) when is_function(method) do
    name = name || self()

    state = %Reactive{
      method: method,
      name: name,
      opts: opts,
      call_id: 0,
      state: :stale,
      listeners: %{}
    }

    if opts[:immediate] do
      if name == self() do
        Reactive.ETS.set(Reactive.ETS.Immediate, :process, name)
      end

      {
        :ok,
        state,
        {:continue, {:compute, :noreply}}
      }
    else
      {
        :ok,
        state
      }
    end
  end

  @doc false
  @impl true
  def handle_call(
        {:set, method},
        from,
        %Reactive{name: name, opts: opts, call_id: call_id} = full_state
      )
      when is_function(method) do
    Reactive.ETS.set(Reactive.ETS.Method, name, method)

    {
      :noreply,
      %Reactive{
        full_state
        | method: method,
          call_id: call_id + 1,
          state: :stale
      },
      {
        :continue,
        case opts[:immediate] do
          true -> {:compute, {from, :ok}}
          _ -> {:mark_listeners_stale, {from, :ok}}
        end
      }
    }
  end

  @doc false
  @impl true
  def handle_call(
        {:stale, expected_call_id},
        from,
        %Reactive{call_id: call_id} = full_state
      ) do
    if expected_call_id == call_id do
      {
        :noreply,
        %Reactive{full_state | call_id: call_id + 1, state: :stale},
        {
          :continue,
          {:mark_listeners_stale, {from, :ok}}
        }
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
  def handle_call(
        {:get, dependent_call_id},
        {from, _},
        %Reactive{listeners: listeners} = full_state
      ) do
    state = compute(full_state)

    {
      :reply,
      state,
      %Reactive{
        full_state
        | state: state,
          listeners: listeners |> Map.put(from, dependent_call_id)
      }
    }
  end

  @doc false
  @impl true
  def handle_call({:get_dry}, _, full_state) do
    state = compute(full_state)

    {:reply, state, %Reactive{full_state | state: state}}
  end

  @doc false
  @impl true
  def handle_call({:get_cached}, _, %Reactive{state: state} = full_state) do
    {:reply, state, full_state}
  end

  @doc false
  @impl true
  def handle_call({:can_gc?}, _, %Reactive{state: :stale, opts: opts} = full_state) do
    {:reply, Keyword.get(opts, :gc, true), full_state} |> dbg()
  end

  @impl true
  def handle_call({:can_gc?}, _, %Reactive{opts: opts} = full_state) do
    if Keyword.get(opts, :gc, true) do
      listeners = valid_listeners(full_state.listeners)
      {:reply, map_size(listeners) == 0, %{full_state | listeners: listeners}}
    else
      {:reply, false, full_state}
    end
  end

  @impl true
  def handle_call({:get_call_id}, _, %Reactive{call_id: call_id} = full_state) do
    {:reply, call_id, full_state}
  end

  @impl true
  def handle_call({:compute_if_needed}, from, %{state: :stale} = full_state) do
    {:noreply, full_state, {:continue, {:compute, {from, :changed}}}}
  end

  @impl true
  def handle_call({:compute_if_needed}, _, full_state) do
    {:reply, :ok, full_state}
  end

  @impl true
  def handle_continue({:compute, reply}, state) do
    {
      :noreply,
      %Reactive{state | state: compute(state)},
      {:continue, {:mark_listeners_stale, reply}}
    }
  end

  @impl true
  def handle_continue({:mark_listeners_stale, reply}, %Reactive{listeners: listeners} = state) do
    for listener <- listeners do
      :ok = stale(listener)
    end

    state = %Reactive{state | listeners: %{}}

    case reply do
      {from, args} -> GenServer.reply(from, args)
      _ -> nil
    end

    {:noreply, state}
  end

  @doc false
  defp compute(%Reactive{method: method, call_id: call_id, state: state}) do
    case state do
      :stale -> method.(call_id)
      _ -> state
    end
  end

  @doc false
  defp valid_listeners(listeners) when is_map(listeners) do
    listeners
    |> Enum.to_list()
    |> valid_listeners()
  end

  defp valid_listeners(lst, valid \\ [])

  defp valid_listeners([check | rest], valid) do
    {pid, expected_call_id} = check

    if expected_call_id != get_call_id(pid) do
      valid_listeners(rest, valid)
    else
      valid_listeners(rest, [check | valid])
    end
  end

  defp valid_listeners([], valid) do
    Enum.into(valid, %{})
  end

  defp valid_listeners(map, valid) when is_map(map) and map_size(map) == 0 do
    Enum.into(valid, %{})
  end
end

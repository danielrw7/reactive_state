defmodule Reactive do
  @moduledoc """
  Module to manage reactive state by using GenServer processes ("reactive process" from here on) to manage each piece of state and its relationships to other reactive processes.

  ## Installation

  The package can be installed by adding `reactive_state` to your list of dependencies in `mix.exs`:

  ```elixir
  def deps do
    [
      {:reactive_state, "~> 0.2.3"}
    ]
  end
  ```

  ## Reactive Block

  To automatically import the `reactive/1` and `reactive/2` macros, you can use `use Reactive` which is the equivalent of:

  ```elixir
  import Reactive, only: [reactive: 1, reactive: 2]
  alias Reactive.Ref
  ```

  Example usage:

      iex> use Reactive
      iex> ref = reactive(do: 2)
      iex> ref_squared = reactive do
      ...>   get(ref) ** 2
      ...> end
      iex> Reactive.get(ref_squared)
      4
      iex> Ref.set(ref, 3)
      iex> Reactive.get(ref_squared)
      9

  To set options at the module level, you can pass options, for example:

      iex> defmodule ReactiveExample do
      ...>   use Reactive, reactive: :reactive_protected, ref: :ref_protected, opts: [gc: false]
      ...>
      ...>   def run do
      ...>     value = ref_protected(0)
      ...>     computed = reactive_protected do
      ...>       get(value) + 1
      ...>     end
      ...>     {Ref.get(value), Ref.get(computed)}
      ...>   end
      ...> end
      iex>
      iex> ReactiveExample.run()
      {0, 1}

  ## Working with data directly with `Reactive.Ref`

      iex> alias Reactive.Ref
      iex> ref = Ref.new(0) #PID<0.204.0>
      iex> Ref.get(ref) # or Ref.get(ref)
      0
      iex> Ref.set(ref, 1)
      :ok
      iex> Ref.get(ref)
      1

  ## Supervisor

  By default, new reactive processes will be linked to the current process.
  To override this behavior, pass the `supervisor` keyword arg with the name of your DynamicSupervisor during process creation:

      value = Ref.new(0, supervisor: MyApp.Supervisor)
      computed = reactive supervisor: MyApp.Supervisor do
        get(value) + 1
      end

  You can also pass default options like this:

      use Reactive, ref: :ref, opts: [supervisor: MyApp.Supervisor]
      ...
      value = ref(0)
      computed = reactive do
        get(value) + 1
      end

  ## Process Restarting

  If a reactive process has been killed for any reason, it will be restarted upon a `Reactive.get` or `Ref.get` call:

      iex> use Reactive
      iex> Reactive.Supervisor.ensure_started()
      iex> ref = Ref.new(0)
      iex> DynamicSupervisor.terminate_child(Reactive.Supervisor, ref)
      iex> Ref.get(ref)
      0

  ## Garbage Collection

  The default garbage collection strategy is to kill any processes that were not accessed through
  a `Reactive.get` or `Ref.get` call between GC calls:

      iex> use Reactive
      iex> Reactive.Supervisor.ensure_started()
      iex> ref = Ref.new(0)
      iex> Reactive.Supervisor.gc()
      iex> nil == Reactive.resolve_process(ref)

  Reactive processes can be protected with the `gc` option:

      iex> use Reactive
      iex> Reactive.Supervisor.ensure_started()
      iex> ref = Ref.new(0, gc: false)
      iex> Reactive.Supervisor.gc()
      iex> ^ref = Reactive.resolve_process(ref)

      iex> use Reactive
      iex> Reactive.Supervisor.ensure_started()
      iex> ref = reactive gc: false do
      ...>    # some expensive computation
      ...> end
      iex> Reactive.Supervisor.gc()
      iex> ^ref = Reactive.resolve_process(ref)

  ## Named Process

  You can name a reactive process using the `name` option:

      iex> use Reactive
      iex> Reactive.Supervisor.ensure_started()
      iex> Ref.new(0, name: MyApp.Value)
      iex> reactive name: MyApp.Computed do
      ...>   get(MyApp.Value) + 1
      ...> end
      iex> Ref.get(MyApp.Value)
      0
      iex> Reactive.get(MyApp.Computed)
      1

  ## Proactive Process

  Proactive reactive processes will not trigger immediately after a dependency changes; they must triggered with a call to `Reactive.Supervisor.trigger_proactive`

      iex> use Reactive
      iex> Reactive.Supervisor.ensure_started()
      iex> num = Ref.new(0)
      iex> ref =
      ...>   reactive proactive: true do
      ...>     get(num) + 1
      ...>   end
      iex> Reactive.get_cached(ref)
      1
      iex> Ref.set(num, 1)
      iex> Reactive.Supervisor.trigger_proactive()
      iex> Reactive.get_cached(ref)
      2
  """

  defstruct [
    :pid,
    :method,
    :opts,
    :call_id,
    :state,
    :listeners
  ]

  use GenServer, restart: :transient

  defmacro __using__(opts) do
    if opts[:reactive] || opts[:opts] do
      macro = Keyword.get(opts, :reactive, :reactive)
      ref = opts[:ref]

      quote do
        @default_opts unquote(Keyword.get(opts, :opts, []))

        defmacro unquote(macro)(opts) do
          Reactive.reactive_ast(opts ++ @default_opts)
        end

        defmacro unquote(macro)(opts, do: ast) do
          opts
          |> Keyword.put(:do, ast)
          |> then(&(&1 ++ @default_opts))
          |> Reactive.reactive_ast()
        end

        if unquote(ref) do
          def unquote(ref)(value, opts \\ []) do
            Reactive.Ref.new(value, opts ++ @default_opts)
          end
        end

        alias Reactive.Ref
      end
    else
      quote do
        import Reactive, only: [reactive: 1, reactive: 2]
        alias Reactive.Ref
      end
    end
  end

  @doc false
  def new(%Reactive{opts: opts} = full_state) do
    Reactive.ETS.ensure_started({opts[:ets_base], :all})

    {:ok, pid} =
      case opts[:supervisor] do
        nil ->
          Reactive.start_link(full_state)

        supervisor ->
          DynamicSupervisor.start_child(
            supervisor,
            {Reactive, full_state}
          )
      end

    opts[:name] || pid
  end

  @doc """
  Create a reactive process using a method

      iex> use Reactive
      iex> ref = Ref.new(2)
      iex> ref_squared = Reactive.new(fn call_id ->
      ...>   Reactive.get(ref, call_id: call_id) ** 2
      ...> end)
      iex> Reactive.get(ref_squared)
      4
  """
  def new(method, opts \\ []) when is_function(method) do
    Reactive.new(%Reactive{
      pid: nil,
      method: method,
      opts: opts,
      call_id: -1,
      state: :stale,
      listeners: %{}
    })
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
      iex> ref_squared = Reactive.new(fn from ->
      ...>   Reactive.get(ref, from: from) ** 2
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

  @doc """
  Create a reactive process with options:

  ```elixir
  reactive name: MyApp.SomeValue, gc: false, proactive: true, supervisor: MyApp.DynamicSupervisor do
    # ...
  end
  ```
  """
  defmacro reactive(opts, do: ast) do
    opts
    |> Keyword.put(:do, ast)
    |> Reactive.reactive_ast()
  end

  @doc false
  def reactive_ast(opts) do
    {ast, opts} = Keyword.pop(opts, :do)

    quote do
      Reactive.new(
        fn from ->
          var!(get) = fn ref -> Reactive.Ref.get(ref, from: from) end
          # suppress unused variable warning
          var!(get)
          unquote(Reactive.Macro.traverse(ast))
        end,
        unquote(opts)
      )
    end
  end

  @doc """
  Find a reactive process from a pid or alias.

      iex> use Reactive
      iex> pid = Ref.new(0, name: MyApp.Value)
      iex> true = Reactive.resolve_process(MyApp.Value) == Reactive.resolve_process(pid)

  You can ensure a process will be returned by passing the `create: true` option

  ```elixir
  Reactive.resolve_process(pid, create: true)
  ```
  """
  def resolve_process(name, opts \\ []) do
    pid = Reactive.ETS.get({opts[:ets_base], State}, name).pid
    pid = if Process.alive?(pid), do: pid

    pid =
      case {pid, opts[:create]} do
        {nil, true} ->
          Reactive.ETS.get({opts[:ets_base], State}, name)
          |> Reactive.new()
          |> Reactive.resolve_process()

        {pid, _} ->
          pid
      end

    pid
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
      iex> Reactive.Supervisor.ensure_started()
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
  def set(pid, method, opts \\ []) when is_function(method) do
    case Reactive.resolve_process(pid) do
      nil ->
        Reactive.ETS.get({opts[:ets_base], State}, pid)
        |> Map.put(:method, method)
        |> Reactive.new()

      resolved_pid ->
        GenServer.call(resolved_pid, {:set, method})
    end

    :ok
  end

  @doc """
  Retrieve the state of a reactive process

  ## Example

      iex> ref = Reactive.new(fn _ -> 0 end)
      iex> Reactive.get(ref)
      0
  """
  def get(pid, opts \\ []) do
    Reactive.call(pid, {:get, opts})
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
      nil ->
        :dead

      pid ->
        GenServer.call(pid, {:compute_if_needed})
    end
  end

  @doc false
  def start_link(%Reactive{} = full_state) do
    GenServer.start_link(__MODULE__, full_state)
  end

  @doc false
  @impl true
  def init(%Reactive{opts: opts, call_id: call_id} = full_state) do
    opts =
      opts
      |> Keyword.put_new(:name, self())

    full_state = %Reactive{
      full_state
      | pid: self(),
        opts: opts,
        call_id: call_id + 1
    }

    if opts[:gc] == false do
      Reactive.ETS.set({opts[:ets_base], ProcessOpts}, :no_gc, opts[:name])
    end

    full_state =
      if opts[:proactive] == true do
        Reactive.ETS.set({opts[:ets_base], ProcessOpts}, :proactive, opts[:name])

        state = compute(full_state)
        %Reactive{full_state | state: state}
      else
        full_state
      end
      |> mark_listeners_stale()
      |> commit_to_ets()

    {:ok, full_state}
  end

  @doc false
  @impl true
  def handle_call(
        {:set, method},
        from,
        %Reactive{opts: opts, call_id: call_id} = full_state
      )
      when is_function(method) do
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
        case opts[:proactive] do
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
        {:get, opts},
        from,
        %Reactive{listeners: listeners} = full_state
      ) do
    state = compute(full_state)

    listeners =
      case opts[:from] do
        nil ->
          listeners

        {dependent_name, dependent_call_id} ->
          listeners |> Map.put(dependent_name, dependent_call_id)
      end

    new_state = %Reactive{
      full_state
      | state: state,
        listeners: listeners
    }

    Reactive.ETS.counter({new_state.opts[:ets_base], Counter}, new_state.opts[:name])

    {
      :noreply,
      new_state,
      {:continue, {:commit_to_ets, {from, state}}}
    }
  end

  @doc false
  @impl true
  def handle_call({:get_cached}, _, %Reactive{state: state} = full_state) do
    {:reply, state, full_state}
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
    {:reply, full_state, full_state}
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

    {:noreply, %Reactive{state | listeners: %{}}, {:continue, {:commit_to_ets, reply}}}
  end

  @impl true
  def handle_continue({:commit_to_ets, reply}, %Reactive{} = state) do
    {:noreply, commit_to_ets(state), {:continue, {:optional_reply, reply}}}
  end

  @impl true
  def handle_continue({:optional_reply, reply}, state) do
    case reply do
      {from, :state} -> GenServer.reply(from, state)
      {from, args} -> GenServer.reply(from, args)
      _ -> nil
    end

    {:noreply, state}
  end

  @doc false
  defp compute(%Reactive{opts: opts, method: method, call_id: call_id, state: state}) do
    case state do
      :stale -> method.({opts[:name], call_id})
      _ -> state
    end
  end

  defp mark_listeners_stale(%Reactive{listeners: listeners} = state) do
    for listener <- listeners do
      :ok = stale(listener)
    end

    %Reactive{state | listeners: listeners}
  end

  defp commit_to_ets(%Reactive{opts: opts} = state) do
    Reactive.ETS.set({opts[:ets_base], State}, opts[:name], state)
    state
  end
end

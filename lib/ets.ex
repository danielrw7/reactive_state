defmodule Reactive.ETS do
  @moduledoc false
  require Reactive.ETS

  defmacro is_name_tuple(name) do
    quote do
      is_tuple(unquote(name)) and
        tuple_size(unquote(name)) == 2 and
        is_atom(unquote(name) |> elem(0)) and
        is_atom(unquote(name) |> elem(1))
    end
  end

  @doc false
  def normalize_name({base, name} = full) when is_name_tuple(full) do
    # Elixir.SomeKey
    # 1234567^^^^^^^
    name_string = Atom.to_string(name) |> String.slice(7..-1)
    base_string = Atom.to_string(base || Reactive.ETS)

    String.to_atom("#{base_string}.#{name_string}")
  end

  def normalize_name(name) when is_atom(name) do
    name
  end

  @doc "Start the necessary ETS tables"
  def ensure_started({base, :all}) do
    ensure_started({base, State})
    ensure_started({base, ProcessOpts})
    ensure_started({base, Counter})
  end

  def ensure_started({base, State}) do
    normalize_name({base, State})
    |> ensure_started()
  end

  def ensure_started({base, ProcessOpts}) do
    normalize_name({base, ProcessOpts})
    |> ensure_started([:bag])
  end

  def ensure_started({base, Counter}) do
    normalize_name({base, Counter})
    |> ensure_started()
  end

  @doc "Start an ETS table"
  def ensure_started(name, opts \\ [:set]) when is_atom(name) or is_name_tuple(name) do
    name = normalize_name(name)

    id =
      case :ets.whereis(name) do
        :undefined -> :ets.new(name, [:named_table, :public] ++ opts)
        id -> id
      end

    {:ok, id}
  end

  @doc false
  def get(name, key, default \\ nil) when is_name_tuple(name) do
    name = normalize_name(name)

    case :ets.lookup(name, key) do
      [{_, value}] -> value
      [] -> default
    end
  end

  @doc false
  def get_all(name, key) when is_name_tuple(name) do
    name = normalize_name(name)
    :ets.lookup(name, key)
  end

  @doc false
  def get_all(name) when is_name_tuple(name) do
    name = normalize_name(name)
    :ets.tab2list(name)
  end

  @doc false
  def set(name, key, value) when is_name_tuple(name) do
    name = normalize_name(name)
    :ets.insert(name, {key, value})
  end

  @doc false
  def counter(name, key, value \\ 1, default \\ 0) when is_name_tuple(name) do
    name = normalize_name(name)
    :ets.update_counter(name, key, value, {key, default})
  end

  @doc "Empty ETS table(s)"
  def empty({base, :all}) do
    empty({base, State})
    empty({base, ProcessOpts})
    empty({base, Counter})
  end

  def empty(name) when is_atom(name) or is_name_tuple(name) do
    name = normalize_name(name)

    case :ets.whereis(name) do
      :undefined -> nil
      _ -> :ets.delete_all_objects(name)
    end
  end

  @doc "Reset ETS table"
  def reset(name) when is_name_tuple(name) do
    name = normalize_name(name)

    case :ets.whereis(name) do
      :undefined ->
        ensure_started(name)

      _ ->
        empty(name)
        ensure_started(name)
    end
  end
end

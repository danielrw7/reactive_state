defmodule Reactive.Ref do
  @moduledoc """
  Wrapper to work with reactive state directly

  ## Example

      iex> use Reactive
      iex> ref = Ref.new(0) #PID<0.204.0>
      iex> Ref.get(ref)
      0
      iex> Ref.set(ref, 1)
      :ok
      iex> Ref.get(ref)
      1
  """

  require Reactive

  @doc """
  Create a reactive process

  ## Example

      iex> ref = Ref.new(0)
      iex> Ref.get(ref)
      0
  """
  def new(value) do
    pid = Reactive.new(fn _ -> value end)
    Reactive.get(pid)
    pid
  end

  @doc """
  Set the state for a reactive process

  ## Example

      iex> ref = Ref.new(0)
      iex> Ref.set(ref, 1)
      :ok
      iex> Ref.get(ref)
      1
  """
  def set(pid, value) do
    existing = Reactive.get_cached(pid)

    if value !== existing do
      Reactive.set(pid, fn _ -> value end)
    end
  end

  @doc """
  Set the state for a reactive process through a function that receives the old value

  ## Example

      iex> ref = Ref.new(0)
      iex> Ref.set_fn(ref, fn state -> state + 1 end)
      :ok
      iex> Ref.get(ref)
      1
  """
  def set_fn(pid, value) when is_function(value) do
    existing = Reactive.get_cached(pid)
    new_value = value.(existing)

    if new_value !== existing do
      Reactive.set(pid, fn _ -> new_value end)
    end
  end

  @doc """
  Retrieve the state of a reactive process

  ## Example

      iex> ref = Ref.new(0)
      iex> Ref.get(ref)
      0
  """
  def get(pid) do
    Reactive.get(pid)
  end

  @doc """
  Retrieve the state of a reactive process, and register the current process as dependent of that process, with the call ID of the current process.
  You should use the `Reactive.reactive` macro to manage reactive relationships instead

  ## Example

      iex> ref = Ref.new(0)
      iex> Ref.get(ref)
      0
  """
  def get(pid, call_id) when is_integer(call_id) do
    Reactive.get(pid, call_id)
  end
end

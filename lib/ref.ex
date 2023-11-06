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

      iex> use Reactive
      iex> ref = Ref.new(0)
      iex> Ref.get(ref)
      0
  """
  def new(value, opts \\ []) do
    Reactive.new(fn _ -> value end, opts)
  end

  @doc """
  Set the state for a reactive process

  ## Example

      iex> use Reactive
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

      iex> use Reactive
      iex> Reactive.Supervisor.ensure_started()
      iex> ref = Ref.new(0)
      iex> Ref.set_fn(ref, fn state -> state + 1 end)
      :ok
      iex> Ref.get(ref)
      1
  """
  def set_fn(pid, value) when is_function(value) do
    existing = Reactive.get(pid)
    new_value = value.(existing)

    if new_value !== existing do
      Reactive.set(pid, fn _ -> new_value end)
    end
  end

  @doc """
  Retrieve the state of a reactive process

  ## Example

      iex> use Reactive
      iex> ref = Ref.new(0)
      iex> Ref.get(ref)
      0
  """
  def get(pid, opts \\ []) do
    Reactive.get(pid, opts)
  end
end

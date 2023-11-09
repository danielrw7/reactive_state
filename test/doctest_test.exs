defmodule DoctestsTest do
  use ExUnit.Case

  setup_all do
    Reactive.Supervisor.ensure_started()
    :ok
  end

  setup do
    Reactive.ETS.reset({nil, :all})

    for {_, pid, _, _} <- DynamicSupervisor.which_children(Reactive.Supervisor) do
      DynamicSupervisor.terminate_child(Reactive.Supervisor, pid)
    end

    :ok
  end

  doctest Reactive
  doctest Reactive.Ref
  doctest Reactive.Supervisor
  doctest Reactive.ETS
end

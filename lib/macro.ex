defmodule Reactive.Macro do
  @moduledoc false

  def traverse({:get, pos, args}) do
    {
      {
        :.,
        pos,
        [
          {:get, [], nil}
        ]
      },
      pos,
      args
    }
  end

  def traverse({:reactive, pos, children}) do
    {:reactive, pos, children}
  end

  def traverse({atom, pos, children}) when is_list(children) do
    {atom, pos, children |> Enum.map(&traverse/1)}
  end

  def traverse([{atom, expression} | rest]) when is_atom(atom) do
    [{atom, expression |> traverse} | rest |> traverse]
  end

  def traverse(value) do
    value
  end
end

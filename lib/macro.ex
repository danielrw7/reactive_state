defmodule Reactive.Macro do
  @moduledoc false

  @doc """
      get(ref1)
      if get(ref2) do
        get(ref3)
      else
        get(ref4)
      end

  becomes

      get.(0, ref1)
      if get.(1, ref2) do
        get.(2, ref3)
      else
        get.(3, ref4)
      end
  """
  def traverse({{:get, meta, args}, counter}) do
    ast = {
      {
        :.,
        meta,
        [
          {:get, [], nil}
        ]
      },
      meta,
      [counter | args]
    }

    {ast, counter + 1}
  end

  def traverse({{:reactive, meta, children}, counter}) do
    {{:reactive, meta, children}, counter}
  end

  def traverse({{atom, meta, children}, counter}) when is_list(children) do
    {children, counter} =
      Enum.flat_map_reduce(children, counter, fn child, counter ->
        {child, counter} = traverse({child, counter})
        {[child], counter}
      end)

    {{atom, meta, children}, counter}
  end

  def traverse({[{atom, expression} | rest], counter}) when is_atom(atom) do
    {expression, counter} = traverse({expression, counter})
    {rest, counter} = traverse({rest, counter})
    {[{atom, expression} | rest], counter}
  end

  def traverse({value, counter}) do
    {value, counter}
  end
end

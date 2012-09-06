defmodule Dynamo.Router.Filters do
  @moduledoc """
  This module is responsible for providing filters to a router or Dynamo
  application. A filter is a module that is invoked before, during or
  after a service match.

  While callbacks are executed only if a route match, filters are always
  executed. Callbacks also abort in case a response is set, while filters
  do not halt their execution. In other words, filters are a more low-level
  mechanism, with no conveniences compared to callbacks.

  There is also a difference about ordering. While filters are invoked in
  the order they are declared, regardless of their behavior, callbacks
  always execute prepare callbacks first, followed by the finalize ones.

  ## Examples

      defmodule MyApp do
        use Dynamo.Router
        filter Dynamo.Static.new("/public", :myapp)
      end

  ## Behaviours

  A filter must implement one of the three functions:

  * `prepare/1`  - the filter will be executed before invoking service
  * `service/2`  - the filter will be executed with the service function as argument
  * `finalize/1` - the filter will be executed after invoking the service

  """

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      @__filters []
      @before_compile unquote(__MODULE__)
      import unquote(__MODULE__), only: [filter: 1, prepend_filter: 1, delete_filter: 1]
    end
  end

  @doc false
  defmacro before_compile(module) do
    filters = Module.read_attribute(module, :__filters)

    code = quote(do: super(conn))
    code = Enum.reduce(filters, code, compile_filter(&1, &2))

    quote location: :keep do
      defoverridable [service: 1]
      def service(conn), do: unquote(code)
    end
  end

  @doc """
  Adds a filter to the filter chain.
  """
  defmacro filter(spec) do
    quote do
      @__filters [unquote(spec)|@__filters]
    end
  end

  @doc """
  Prepends a filter to the filter chain.
  """
  defmacro prepend_filter(spec) do
    quote do
      @__filters @__filters ++ [unquote(spec)]
    end
  end

  @doc """
  Deletes a filter from the filter chain.
  """
  defmacro delete_filter(atom) do
    quote do
      atom = unquote(atom)
      @__filters Enum.filter(@__filters, fn(f) -> not unquote(__MODULE__).match?(atom, f) end)
    end
  end

  @doc """
  Matches a filter against the other
  """
  def match?(atom, filter) when is_atom(atom) and is_tuple(filter) do
    elem(filter, 1) == atom
  end

  def match?(atom, atom) when is_atom(atom) do
    true
  end

  def match?(_, _) do
    false
  end

  ## Helpers

  defp compile_filter(filter, acc) do
    { mod, extra } = extract_module_and_arity(filter)

    case Code.ensure_compiled(mod) do
      { :module, _ } ->
        filter = Macro.escape(filter)

        cond do
          function_exported?(mod, :service, 2 + extra)  ->
            quote do
              unquote(filter).service(conn, fn(conn) -> unquote(acc) end)
            end
          function_exported?(mod, :prepare, 1 + extra)  ->
            quote do
              conn = unquote(filter).prepare(conn)
              unquote(acc)
            end
          function_exported?(mod, :finalize, 1 + extra)  ->
            quote do
              unquote(filter).finalize(unquote(acc))
            end
          true ->
            raise "filter #{inspect filter} does not implement any of the required functions"
        end
      { :error, _ } ->
        raise "could not find #{inspect filter} to be used as filter"
    end
  end

  defp extract_module_and_arity(h) when is_atom(h) do
    { h, 0 }
  end

  defp extract_module_and_arity(h) when is_tuple(h) and is_atom(elem(h, 1)) do
    { elem(h, 1), 1 }
  end
end
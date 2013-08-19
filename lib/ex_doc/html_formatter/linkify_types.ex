# Helpers to create links in types. 
defmodule ExDoc.HTMLFormatter.LinkifyTypes do

@moduledoc false

@call_rx(%r/(?:[[:upper:]_:][[:alnum:]_]*\.)*(?:[[:lower:]_][[:alnum:]_]*)(?:\(\))?/u)

@remote_elixir_doc_base("http://elixir-lang.org/docs/master/")

@doc """
Add links to the given type string.

Returns the string, converted to HTML.

This is intended to be used only by the HTML formatter.
"""
@spec linkify(String.t, [atom], [{ { Module.t, atom }, :current | :elixir }]) :: String.t
def linkify(s, locals, remotes) do
  Enum.map_join(classify(s), "", &do_linkify(&1, locals, remotes))
end

defp do_linkify({:normal, s}, _, _) do
  h(s)
end
defp do_linkify({:local, s, t, a}, locals, _) do
  # Not everything that appears to be a local call really is one. For example
  # it could be is_subtype (syntax) or the name of the spec being defined
  # (which we also don't want to link). The `locals` list contains what we want
  # to generate links for.
  if {t, a} in locals do
    "<a href=\"#t:#{atom_to_binary(t)}/#{a}\">#{h(s)}</a>"
  else
    h(s)
  end
end
defp do_linkify({:remote, s, m, t, a}, _, remotes) do
  mn = if (String.starts_with?(atom_to_binary(m), "Elixir.")) do
         # A module name like Dict is officially known to Erlang as
         # 'Elixir.Dict' and atom_to_binary reflects that. Strip off the prefix.
         String.split(atom_to_binary(m), ".", global: false) |> tl |> hd
       else
         atom_to_binary(m)
       end
  case ListDict.get(remotes, {m, t, a}, 0) do
    :current ->
      # Link in the current project. So just point at a file in the local
      # directory.
      "<a href=\"#{mn}.html#t:#{t}/#{a}\">#{h(s)}</a>"
    :elixir ->
      "<a href=\"#{@remote_elixir_doc_base}#{mn}.html#t:#{t}/#{a}\">#{h(s)}</a>"
    _ ->
      h(s)
  end
end

# Splits up the string into non-call parts and call parts. The call parts are
# either local calls (unqualified) or remote calls.
@spec classify(String.t) :: 
  [ { :normal, String.t } | { :local, String.t, atom } | { :remote, String.t, Module.t, atom } ]
defp classify(s) do
  # flatten works because the sublists only contain one element each (no
  # captures in the regex)
  call_indexes = Regex.scan(@call_rx, s, return: :index) |> List.flatten
  
  { parts_, last } = Enum.map_reduce(call_indexes, 0, fn {start, len}, last ->
    before = :erlang.binary_part(s, last, start - last)
    call = :erlang.binary_part(s, start, len)
    { [{ :normal, before }, { :call, call, start, len }], start + len }
  end)
  last_str = :erlang.binary_part(s, last, size(s) - last)
  parts = if last_str == "" do
            List.flatten(parts_)
          else
            List.flatten(parts_) ++ [{ :normal, last_str }]
          end
  Enum.map(parts, classify_part(s, &1))
end

defp classify_part(s, {:call, matched, start, len}) do
  # Due to greedy regexes this splits on the last dot.
  # For remote types it also takes care of removing any trailing () before
  # converting to atom.
  case Regex.run(%r/(.*)\.([[:alnum:]_]+)(?:\(\))?/, matched) do
    [_, mod_str, type_str] ->
      mod = if String.starts_with?(mod_str, ":") do
              binary_to_atom(:erlang.binary_part(mod_str, 1, size(mod_str) - 1))
            else
              # This is the difference between :Dict and :"Dict".
              binary_to_atom("Elixir." <> mod_str)
            end
      if (String.ends_with?(matched, "()")) do
        # Nullary type.
        { :remote, matched, mod, binary_to_atom(type_str), 0 }
      else
        # Technically it's allowed to express a nullary type call as "foo( )"
        # (with a space). The Macro.to_string function never does that, so it's
        # safe to assume that if the argument list isn't totally empty there's
        # at least one argument.
        { arity, _ } = determine_arity(s, start+len+1, 1, 1)
        { :remote, matched, mod, binary_to_atom(type_str), arity }
      end
    nil ->
      if String.ends_with?(matched, "()") do
        { :local, matched, binary_to_atom(:erlang.binary_part(matched, 0, size(matched)-2)), 0 }
      else
        { arity, _ } = determine_arity(s, start+len+1, 1, 1)
        { :local, matched, binary_to_atom(matched), arity }
      end
  end
end
defp classify_part(_, tup) do
  tup
end

# Byte by byte scanning for comma's inside list like syntax (argument lists,
# lists, tuples).
defp determine_arity(_, pos, 0, arity) do
  { arity, pos }
end
# This case shouldn't be needed, but just in case...
defp determine_arity(s, pos, _, arity) when pos >= size(s) do
  { arity, pos }
end
defp determine_arity(s, pos, depth, arity) do
  case :binary.at(s, pos) do
    c when c in [?(, ?<, ?{, ?[]      -> determine_arity(s, pos+1, depth+1, arity)
    c when c in [?), ?>, ?}, ?]]      -> determine_arity(s, pos+1, depth-1, arity)
    ?, when depth == 1                -> determine_arity(s, pos+1, depth, arity+1)
    _                                 -> determine_arity(s, pos+1, depth, arity)
  end
end

# Shortcut for escape_html.
defp h(s) do
  ExDoc.HTMLFormatter.Templates.escape_html(s)
end

end


defmodule RiemannxTest.Utils do
  def term_to_port(<<"#Port<0.", id :: binary>> ) do
    n = id |> String.trim_trailing(">") |> String.to_integer()
    term_to_port(n)
  end
  def term_to_port(n) when is_integer(n) do
    name   = Node.self() |> Atom.to_charlist() |> :erlang.iolist_to_binary()
    length = :erlang.iolist_size(name)
    self   = :erlang.term_to_binary(self())
    vsn    = :binary.last(self)
   <<131, 102, 100,
     length :: size(2)-unit(8),
     name :: size(length)-binary,
     n :: size(4)-unit(8),
     vsn :: size(8)>> |> :erlang.binary_to_term
  end
end
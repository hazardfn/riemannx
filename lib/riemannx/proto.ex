defmodule Riemannx.Proto do
  use Protobuf, from: Path.expand("riemann.proto", __DIR__)
  @external_resource Path.expand("riemann.proto", __DIR__)
  
  use_in "Event", Riemannx.Proto.Helpers.Event
  use_in "Msg",   Riemannx.Proto.Helpers.Msg
  use_in "Attribute", Riemannx.Proto.Helpers.Attribute
end
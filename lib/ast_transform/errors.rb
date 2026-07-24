# frozen_string_literal: true

module ASTTransform
  # Raised by authoring helpers (e.g. +s_at+) when a node that must carry a source location does not have one.
  class MissingLocationError < StandardError; end

  # Raised at construction when a Thunk node's children violate its invariants (missing token, empty body). Every
  # construction path funnels through Thunk#initialize — including Processor rebuilds — so a malformed thunk cannot
  # exist in a tree.
  class MalformedThunkError < StandardError; end

  # Raised at lowering when a thunk cannot be placed: its body's source lines fall after the execution point (the
  # hidden proc's text IS its assignment, so a call can never textually precede the body), or two occurrences of the
  # same thunk carry diverging bodies.
  class ThunkPlacementError < StandardError; end

  # Raised as the emitter's postcondition when a custom node type (ast_* markers or types registered on
  # ASTTransform::Node) reaches the unparse boundary instead of being lowered by the stage that understands it.
  class UnloweredNodeTypeError < StandardError; end
end

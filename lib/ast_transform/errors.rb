# frozen_string_literal: true
module ASTTransform
  # Raised by authoring helpers (e.g. +s_at+) when a node that must carry a
  # source location does not have one.
  class MissingLocationError < StandardError; end

  # Raised by +defer+ when a deferred statement contains control flow that
  # would re-bind to the deferral lambda (e.g. +return+), silently changing
  # the meaning of the user's code.
  class NonDeferrableError < StandardError; end

  # Raised at emission when deferral markers cannot be reconciled: a
  # placement without any execution point, an execution point without a
  # placement (or preceding it), or a duplicate placement.
  class UnmatchedDeferralError < StandardError; end

  # Raised as the emitter's postcondition when a custom node type (ast_*
  # markers or types registered on ASTTransform::Node) reaches the unparse
  # boundary instead of being lowered by the stage that understands it.
  class UnloweredNodeTypeError < StandardError; end
end

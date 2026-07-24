# frozen_string_literal: true

require 'ast_transform/node'
require 'ast_transform/errors'

module ASTTransform
  # The reordering primitive: an eagerly built wrapper node, spliced wherever the wrapped statements must EXECUTE —
  # statement position or composed inside an expression (e.g. an assert_raises block body). Its body keeps its own
  # source locations, and the lowering derives the wrapper's textual placement from them (see ThunkLowering), so the
  # statements still emit on their original lines even though execution waits.
  #
  # Children are +[token, *body_statements]+ and the invariants are enforced here in +initialize+, which every
  # construction path shares — +s+ routing, the +thunk+ helper, and Processor rebuilds (+updated+ re-initializes).
  # Build thunks with +TransformationHelper#thunk+; reuse the same node to execute one body from several points
  # (multiplexing).
  #
  # Runtime semantics are near-transparent (proc lowering): +return+ still returns from the enclosing method, and
  # locals the body assigns stay method-scope. See ThunkLowering for the full contract.
  class Thunk < Node
    register :ast_thunk

    # The identity of a Thunk across transformation passes: Processor and Node#updated rebuilds create new node
    # objects, so node identity does not survive — but children DO (carried by reference through every rebuild). Every
    # rebuild of a thunk therefore carries this same id object, and the lowering groups occurrences by its object
    # identity: one proc, one call per occurrence. Minted internally by the +thunk+ helper, never handled by authors.
    # No behavior — a named class over a bare Object.new only for self-documenting AST dumps and greppability.
    class Id; end

    def initialize(type, children, properties = {})
      id, *body = children
      unless id.is_a?(ASTTransform::Thunk::Id)
        raise MalformedThunkError,
          "a Thunk's first child must be its #{Thunk::Id} (got #{id.class}); build thunks with the " \
            "thunk(*statements) helper"
      end
      raise MalformedThunkError, "a Thunk must wrap at least one statement" if body.empty?

      # Captured before super (which freezes the node); frozen so the shared array cannot be mutated out from under
      # +children+. Rebuilds via +updated+ re-run initialize, so the capture can never go stale.
      @id = id
      @body = body.freeze

      super
    end

    # Retrieves the Thunk's id.
    # @return [ASTTransform::Thunk::Id] The Id.
    attr_reader(:id)

    # Retrieves the Thunk's body.
    #
    # @note Same as the +Parser::AST::Node#children+
    # @return [Array<Parser::AST::Node>] The nodes forming the body of the Thunk.
    attr_reader(:body)
  end
end

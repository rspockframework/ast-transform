# frozen_string_literal: true

require 'ast_transform/node'
require 'ast_transform/errors'

module ASTTransform
  # The reordering primitive: an eagerly built wrapper node, spliced wherever
  # the wrapped statements must EXECUTE — statement position or composed
  # inside an expression (e.g. an assert_raises block body). Its body keeps
  # its own source locations, and the lowering derives the wrapper's textual
  # placement from them (see ThunkLowering), so the statements still emit on
  # their original lines even though execution waits.
  #
  # Children are +[token, *body_statements]+ and the invariants are enforced
  # here in +initialize+, which every construction path shares — +s+ routing,
  # the +thunk+ helper, and Processor rebuilds (+updated+ re-initializes).
  # Build thunks with +TransformationHelper#thunk+; reuse the same node to
  # execute one body from several points (multiplexing).
  #
  # Runtime semantics are near-transparent (proc lowering): +return+ still
  # returns from the enclosing method, and locals the body assigns stay
  # method-scope. See ThunkLowering for the full contract.
  class Thunk < Node
    register :ast_thunk

    def initialize(type, children, properties = {})
      token, *body = children
      unless token.is_a?(ThunkToken)
        raise MalformedThunkError,
          "a Thunk's first child must be its ThunkToken (got #{token.class}); " \
            "build thunks with the thunk(*statements) helper"
      end
      raise MalformedThunkError, "a Thunk must wrap at least one statement" if body.empty?

      super
    end

    def token = children[0]

    def body = children.drop(1)
  end

  # The identity of a Thunk across transformation passes: Processor and
  # Node#updated rebuilds create new node objects, so node identity does not
  # survive — but children DO (carried by reference through every rebuild).
  # Every rebuild of a thunk therefore carries this same token object, and
  # the lowering groups occurrences by its object identity: one proc, one
  # call per occurrence. Minted internally by the +thunk+ helper, never
  # handled by authors. No behavior — a named class over a bare Object.new
  # only for self-documenting AST dumps and greppability.
  class ThunkToken
    def inspect
      "#<ASTTransform::ThunkToken 0x#{object_id.to_s(16)}>"
    end
  end
end

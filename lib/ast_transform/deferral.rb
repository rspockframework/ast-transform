# frozen_string_literal: true
require 'ast_transform/errors'

module ASTTransform
  # The handle returned by +defer+: not a node, a pair of nodes. Both markers
  # are ordinary nodes in the ast_transform IR — the emitter keys on node type
  # and token, never on any class — created together so the pair cannot be
  # mismatched.
  #
  # placement:: (:ast_deferred, token, (:begin, ...)) — the deferred body,
  #             spliced at the statements' SOURCE position; lowered to
  #             +__ast_deferred_<n>__ = proc { ... }+ (plus pre-declarations
  #             for the locals the body assigns — see DeferralLowering).
  # execution:: (:ast_deferred_call, token) — loc-less, spliced (or composed
  #             into an expression, e.g. an assert_raises block body) at the
  #             execution point; lowered to +__ast_deferred_<n>__.call+.
  Deferral = Data.define(:placement, :execution)

  # The pairing mechanism between the two halves of a Deferral: it answers
  # "which proc does this call marker invoke?" when a scope holds several
  # deferrals. The markers cannot reference each other's nodes — Processor and
  # Node#updated rebuilds create new node objects, so node identity does not
  # survive transformation passes. Children DO survive (carried by reference
  # through every rebuild), so both markers carry this same child object and
  # the emitter pairs by its object identity. No behavior needed — a named
  # class over a bare Object.new only for self-documenting AST dumps and
  # greppability.
  class DeferralToken
    def inspect
      "#<ASTTransform::DeferralToken 0x#{object_id.to_s(16)}>"
    end
  end
end

# frozen_string_literal: true
require 'ast_transform/node'
require 'ast_transform/errors'
require 'ast_transform/transformation_helper'

module ASTTransform
  # Lowers deferral markers into plain Ruby nodes ahead of emission:
  #
  #   (:ast_deferred, token, (:begin, ...)) => x = x; __ast_deferred_<n>__ = proc { ... }
  #   (:ast_deferred_call, token)           => __ast_deferred_<n>__.call
  #
  # The closure is a non-lambda proc on purpose: `return` inside a proc
  # returns from the method where the proc was defined, and placement and
  # execution always share one method activation (the hidden lvar cannot be
  # referenced across a def boundary), so a deferred `return` keeps its
  # original meaning. Jump keywords whose owner lies outside the deferred
  # statements keep Ruby's native behavior — no transform-time validation:
  # what a transform chooses to defer is the transform author's call.
  #
  # The `x = x` pre-declarations cover every local the deferred statements
  # assign at method scope. A local first assigned inside a block literal is
  # block-local, so without a textual method-scope assignment before the
  # proc, deferred assignments would be invisible to the statements that
  # read them after the execution point. Self-assignment registers the name
  # (nil until the deferred code runs — exactly what an unexecuted
  # assignment yields) without clobbering an already-assigned value.
  #
  # Hidden lvar names are assigned per token in encounter order, so they are
  # stable within a file and never collide. Pairing is by token object
  # identity (see DeferralToken).
  #
  # Reconciliation is a static count of markers in the tree, not of runtime
  # executions — a call under a conditional legitimately executes zero-or-more
  # times. One placement may have many calls (multiplexing); it must have at
  # least one, textually after it (the proc must exist before it is called).
  class DeferralLowering
    include TransformationHelper

    def initialize
      @names_by_token = {}.compare_by_identity
      @called_tokens = {}.compare_by_identity
    end

    # @param node [Parser::AST::Node] tree possibly containing deferral markers
    # @return [Parser::AST::Node] tree with markers lowered to plain Ruby
    # @raise [UnmatchedDeferralError] on missing call, orphan or premature
    #   call, or duplicate placement
    def run(node)
      lowered = lower(node)

      unexecuted = @names_by_token.keys.reject { |token| @called_tokens.key?(token) }
      unless unexecuted.empty?
        raise UnmatchedDeferralError,
          "deferred statements were placed but never executed (#{unexecuted.size} deferral(s) " \
            "without an execution point); the deferred code would silently never run"
      end

      lowered
    end

    private

    def lower(node)
      return node unless node.is_a?(::Parser::AST::Node)

      case node.type
      when :ast_deferred then lower_placement(node)
      when :ast_deferred_call then lower_call(node)
      else
        node.updated(nil, node.children.map { |child| lower(child) })
      end
    end

    def lower_placement(node)
      token, body = node.children
      if @names_by_token.key?(token)
        raise UnmatchedDeferralError,
          "duplicate deferral placement: the hidden proc would be assigned twice"
      end

      name = :"__ast_deferred_#{@names_by_token.size + 1}__"
      @names_by_token[token] = name

      deferred_assignment = s(:lvasgn, name, s(:block, s(:send, nil, :proc), s(:args), lower(body)))
      pre_declarations = method_scope_assignments(body).map { |local| s(:lvasgn, local, s(:lvar, local)) }
      return deferred_assignment if pre_declarations.empty?

      # A loc-less :begin in statement position; the emitter flattens it into
      # the surrounding statement stream so the proc body still aligns.
      s(:begin, *pre_declarations, deferred_assignment)
    end

    def lower_call(node)
      token = node.children[0]
      name = @names_by_token[token]
      unless name
        raise UnmatchedDeferralError,
          "deferral execution point encountered without a preceding placement; " \
            "the placement must appear textually before its execution"
      end

      @called_tokens[token] = true
      s(:send, s(:lvar, name), :call)
    end

    # Node types opening a new local-variable scope: assignments inside them
    # were invisible to the method scope in the original source too, so they
    # get no pre-declaration.
    NEW_SCOPE_TYPES = [:def, :defs, :class, :module, :sclass].freeze
    # Block literals: locals first assigned inside them are block-local (the
    # same lexical rule the pre-declarations exist to work around), but their
    # callee/arguments evaluate at method scope and are still descended.
    BLOCK_TYPES = [:block, :numblock, :itblock].freeze

    # Locals the deferred statements assign at method scope, in
    # first-assignment order (covers masgn/op_asgn targets — they all carry
    # :lvasgn nodes).
    def method_scope_assignments(node, names = [])
      return names unless node.is_a?(::Parser::AST::Node)
      return names if NEW_SCOPE_TYPES.include?(node.type)

      names << node.children[0] if node.type == :lvasgn && !names.include?(node.children[0])

      children = BLOCK_TYPES.include?(node.type) ? [node.children[0]] : node.children
      children.each { |child| method_scope_assignments(child, names) }
      names
    end
  end
end

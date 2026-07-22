# frozen_string_literal: true
require 'ast_transform/node'
require 'ast_transform/errors'
require 'ast_transform/transformation_helper'

module ASTTransform
  # Lowers deferral markers into plain Ruby nodes ahead of emission:
  #
  #   (:ast_deferred, token, (:begin, ...)) => __ast_deferred_<n>__ = -> { ... }
  #   (:ast_deferred_call, token)           => __ast_deferred_<n>__.call
  #
  # Hidden lvar names are assigned per token in encounter order, so they are
  # stable within a file and never collide. Pairing is by token object
  # identity (see DeferralToken).
  #
  # Reconciliation is a static count of markers in the tree, not of runtime
  # executions — a call under a conditional legitimately executes zero-or-more
  # times. One placement may have many calls (multiplexing); it must have at
  # least one, textually after it (the lambda must exist before it is called).
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
          "duplicate deferral placement: the hidden lambda would be assigned twice"
      end

      name = :"__ast_deferred_#{@names_by_token.size + 1}__"
      @names_by_token[token] = name

      s(:lvasgn, name, s(:block, s(:lambda), s(:args), lower(body)))
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
  end
end

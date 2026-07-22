# frozen_string_literal: true
require 'parser'
require 'ast_transform/errors'

module ASTTransform
  # Validates that statements are safe to defer. Deferral wraps statements in
  # a lambda; control-flow keywords bind to the nearest enclosing scope, so
  # keywords written against the original scope would silently re-bind to the
  # lambda. This guard turns that semantics hazard into a transform-time error.
  #
  # Scope rules mirror Ruby's:
  # - +break+/+next+/+redo+/+retry+ are owned by the nearest block, so blocks
  #   are not descended for them.
  # - +return+ penetrates plain blocks (it returns from the enclosing method),
  #   so blocks ARE descended for it. Only defs and lambdas absorb it.
  class ControlFlowGuard
    BLOCK_OWNED_TYPES = [:break, :next, :redo, :retry].freeze
    METHOD_OWNED_TYPES = [:return].freeze
    BLOCK_TYPES = [:block, :numblock].freeze
    METHOD_DEFINITION_TYPES = [:def, :defs].freeze

    # @param statements [Array<Parser::AST::Node>] statements about to be deferred
    # @return [void]
    # @raise [NonDeferrableError] when a statement contains control flow that
    #   would re-bind to the deferral lambda
    def check!(statements)
      statements.each { |statement| check_node(statement, BLOCK_OWNED_TYPES + METHOD_OWNED_TYPES) }
      nil
    end

    private

    def check_node(node, hazardous_types)
      return unless node.is_a?(::Parser::AST::Node)

      if hazardous_types.include?(node.type)
        raise NonDeferrableError,
          "cannot defer a statement containing `#{node.type}`: it would re-bind " \
            "to the deferral lambda and change the code's meaning"
      end

      remaining = remaining_hazards(node, hazardous_types)
      return if remaining.empty?

      node.children.each { |child| check_node(child, remaining) }
    end

    def remaining_hazards(node, hazardous_types)
      return [] if METHOD_DEFINITION_TYPES.include?(node.type) || lambda_block?(node)
      return hazardous_types - BLOCK_OWNED_TYPES if BLOCK_TYPES.include?(node.type)

      hazardous_types
    end

    # A literal lambda parses as (block (lambda) args body); Kernel#lambda as
    # (block (send nil :lambda) args body). Unlike plain blocks, both absorb
    # +return+.
    def lambda_block?(node)
      return false unless BLOCK_TYPES.include?(node.type)

      callee = node.children[0]
      return false unless callee.is_a?(::Parser::AST::Node)

      callee.type == :lambda || (callee.type == :send && callee.children == [nil, :lambda])
    end
  end
end

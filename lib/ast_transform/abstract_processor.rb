# frozen_string_literal: true

require "ast_transform/transformation_helper"

module ASTTransform
  # Shared traversal core for tree passes. Parser::AST::Processor is a rewriting walker — every visit functionally
  # rebuilds the tree — so transformation and analysis share one engine and differ only in what they keep:
  # AbstractTransformation's +run+ returns the rebuilt tree, AbstractAnalysis's +run+ discards it and returns the
  # harvested results. Subclass one of those leaves rather than this class.
  class AbstractProcessor < Parser::AST::Processor
    include TransformationHelper

    # Used internally by Parser::AST::Processor to process each node. DO NOT OVERRIDE.
    def process(node)
      return node unless node.is_a?(Parser::AST::Node)

      process_node(node)
    end

    # Thunks are framework-owned IR: descend into the body so passes that don't know about thunks still process the
    # wrapped statements. Without this, Processor's handler_missing default would pass the node through opaquely,
    # hiding the body from every later pass. The token (first child) is not a node and passes through untouched.
    def on_ast_thunk(node)
      node.updated(nil, [node.children[0], *process_all(node.children.drop(1))])
    end

    private

    # Processes the given +node+.
    # Note: If you want to do processing on each node, override this.
    #
    # @param node [Parser::AST::Node] The node being visited.
    #
    # @return [Parser::AST::Node] The rebuilt node.
    def process_node(node)
      method(:process).super_method.call(node)
    end
  end
end

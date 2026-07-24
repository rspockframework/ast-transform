# frozen_string_literal: true

require 'parser'

module ASTTransform
  # Base class for custom IR nodes. Transform authors subclass it and register a custom node type to get type-routed
  # construction from +s+ with domain accessors:
  #
  #   class InteractionNode < ASTTransform::Node
  #     register :rspock_interaction
  #
  #     def cardinality = children[0]
  #   end
  #
  #   s(:rspock_interaction, ...) # => InteractionNode
  #
  # Custom node *types* are IR between stages that understand them and must be lowered before emission (the emitter
  # enforces this). Standard-typed nodes deliberately stay plain Parser::AST::Node everywhere — parsed and +s+-built
  # alike: AST::Node#eql? compares class, and Unparser verifies dynamic-string emission by re-parsing and
  # eql?-comparing, so a custom class on a standard type breaks emission.
  class Node < ::Parser::AST::Node
    class << self
      # Registers +self+ as the class to construct for +type+ nodes.
      #
      # @param type [Symbol] the custom node type routed to this class
      # @return [void]
      def register(type)
        Node.registry[type] = self
      end

      # Builds a node of +type+: registered types construct their custom class, everything else a plain
      # Parser::AST::Node.
      #
      # @param type [Symbol] node type
      # @param children [Array] child nodes / literals
      # @param properties [Hash] node properties (e.g. location:)
      # @return [Parser::AST::Node]
      def build(type, children, properties = {})
        klass = Node.registry.fetch(type, ::Parser::AST::Node)
        klass.new(type, children, properties)
      end

      def registry
        @registry ||= {}
      end
    end
  end
end

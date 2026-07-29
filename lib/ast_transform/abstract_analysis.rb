# frozen_string_literal: true

require "ast_transform/abstract_processor"

module ASTTransform
  # Base class for read-only analysis passes: subclass, harvest state in +on_*+ handlers (always call +super+ so
  # traversal continues), and expose results through readers. The walk still functionally rebuilds the tree —
  # Parser::AST::Processor has no read-only mode — but +run+ discards the rebuilt tree, so handlers never need to
  # care what they return.
  #
  #   class SendCounter < ASTTransform::AbstractAnalysis
  #     attr_reader :count
  #
  #     def initialize
  #       @count = 0
  #       super
  #     end
  #
  #     def on_send(node)
  #       @count += 1
  #       super
  #     end
  #   end
  #
  #   SendCounter.new.run(SourceParser.new.parse(source)).count
  class AbstractAnalysis < AbstractProcessor
    # Runs this analysis on +node+, discarding the rebuilt tree.
    # Note: If you want to add one-time setup or result finalization, override this, then call super.
    #
    # @param node [Parser::AST::Node] The node to be analyzed.
    #
    # @return [ASTTransform::AbstractAnalysis] self, so callers can chain result readers off the run.
    def run(node)
      process(node)
      self
    end
  end
end

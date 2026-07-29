# frozen_string_literal: true

require "test_helper"
require "transformation_helper"
require "ast_transform/abstract_analysis"

module ASTTransform
  class AbstractAnalysisTest < Minitest::Test
    extend ASTTransform::Declarative
    include ASTTransform::Helpers::TransformationHelper

    class SendNameCollector < ASTTransform::AbstractAnalysis
      attr_reader :names

      def initialize
        @names = []
        super
      end

      def on_send(node)
        @names << node.children[1]
        super
      end
    end

    test "#run returns the analysis instance" do
      analysis = SendNameCollector.new

      assert_same analysis, analysis.run(s(:send, nil, :a))
    end

    test "#run harvests from every matching node in the tree" do
      ast = ASTTransform::SourceParser.new.parse(<<~CODE)
        foo
        bar(baz)
      CODE

      assert_equal [:foo, :bar, :baz], SendNameCollector.new.run(ast).names
    end

    test "#run returns the analysis instance for non-node input without harvesting" do
      analysis = SendNameCollector.new

      assert_same analysis, analysis.run(Object.new)
      assert_empty analysis.names
    end

    test "#run descends into thunk bodies" do
      ast = s(:begin, thunk(s(:send, nil, :hidden)))

      assert_equal [:hidden], SendNameCollector.new.run(ast).names
    end

    test "#run leaves the analyzed tree equal to a fresh parse" do
      source_parser = ASTTransform::SourceParser.new
      ast = source_parser.parse("foo(bar)")
      SendNameCollector.new.run(ast)

      assert_equal source_parser.parse("foo(bar)"), ast
    end
  end
end

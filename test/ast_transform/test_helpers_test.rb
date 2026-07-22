# frozen_string_literal: true
require 'test_helper'
require 'ast_transform/test_helpers'
require 'ast_transform/abstract_transformation'

module ASTTransform
  class TestHelpersTest < Minitest::Test
    extend ASTTransform::Declarative
    include ASTTransform::TestHelpers

    # Rewrites statements in place (keeps anchors) — always aligned.
    class InPlaceTransformation < ASTTransform::AbstractTransformation
      private

      def process_node(node)
        return method(:process).super_method.call(node) unless node.type == :send && node.children[0].nil?

        node.updated(nil, [nil, :"renamed_#{node.children[1]}"])
      end
    end

    ALIGNED_SOURCE = <<~HEREDOC
      first_call

      second_call
    HEREDOC

    test "assert_line_aligned passes for an in-place transform" do
      assert_line_aligned(ALIGNED_SOURCE, InPlaceTransformation.new)
    end

    test "assert_line_aligned passes with no transformations" do
      assert_line_aligned(ALIGNED_SOURCE)
    end

    test "assert_backtrace_lines passes when the raise cites its source line" do
      source = <<~HEREDOC
        value = 1

        raise "expected boom" if value == 1
      HEREDOC

      assert_backtrace_lines(source, path: File.expand_path('tmp/test/helpers_fixture.rb'), raise_at: 3)
    end
  end
end

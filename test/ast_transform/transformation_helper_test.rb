# frozen_string_literal: true
require 'test_helper'
require 'ast_transform/transformation_helper'
require 'ast_transform/transformer'

module ASTTransform
  class TransformationHelperTest < Minitest::Test
    extend ASTTransform::Declarative
    include ASTTransform::TransformationHelper

    class RegisteredNode < ASTTransform::Node
      register :ast_transform_test_registered

      def payload = children[0]
    end

    def parse(source)
      ASTTransform::Transformer.new.build_ast(source)
    end

    test "s builds a plain loc-less node" do
      node = s(:send, nil, :foo)

      assert_instance_of ::Parser::AST::Node, node
      assert_nil node.loc
    end

    test "s routes registered custom types to their class" do
      node = s(:ast_transform_test_registered, 42)

      assert_instance_of RegisteredNode, node
      assert_equal 42, node.payload
    end

    test "s_at anchors a fresh node to another node's source location" do
      anchor = parse("foo(1)\n")

      node = s_at(anchor, :send, nil, :bar)

      assert_equal :bar, node.children[1]
      assert_equal anchor.loc.line, node.loc.line
      assert_equal anchor.loc.expression, node.loc.expression
    end

    test "s_at raises MissingLocationError for loc-less anchors" do
      error = assert_raises(MissingLocationError) { s_at(s(:send, nil, :foo), :send, nil, :bar) }

      assert_includes error.message, 'send'
    end

    test "defer returns a Deferral whose markers share a token" do
      statements = parse("foo\nbar\n").children

      deferral = defer(*statements)

      assert_equal :ast_deferred, deferral.placement.type
      assert_equal :ast_deferred_call, deferral.execution.type
      assert_same deferral.placement.children[0], deferral.execution.children[0]
      assert_instance_of DeferralToken, deferral.placement.children[0]
    end

    test "DeferralToken#inspect names the class so AST dumps are self-documenting" do
      token = defer(parse("foo\n")).placement.children[0]

      assert_match(/\A#<ASTTransform::DeferralToken 0x\h+>\z/, token.inspect)
    end

    test "defer rejects statements containing return" do
      statement = parse("return 1 if early\n")

      assert_raises(NonDeferrableError) { defer(statement) }
    end

    test "defer rejects break and next at the deferred scope's level" do
      assert_raises(NonDeferrableError) { defer(parse("break\n")) }
      assert_raises(NonDeferrableError) { defer(parse("next\n")) }
    end

    test "defer allows break and next owned by a nested block" do
      statement = parse("items.each { |item| next if item.nil? }\n")

      deferral = defer(statement)

      assert_equal :ast_deferred, deferral.placement.type
    end

    test "defer rejects return inside a nested block (it penetrates to the method)" do
      statement = parse("items.each { |item| return item }\n")

      assert_raises(NonDeferrableError) { defer(statement) }
    end

    test "defer allows return absorbed by a nested def or lambda" do
      assert_equal :ast_deferred, defer(parse("def helper = (return 1)\n")).placement.type
      assert_equal :ast_deferred, defer(parse("callback = -> { return 1 }\n")).placement.type
    end

    test "run_after replaces the run with a placement and inserts the execution after the anchor" do
      setup_statement, when_statement, interaction = parse("given\nwhen_body\ninteraction\n").children

      reordered = run_after([setup_statement, when_statement, interaction], run: [when_statement], after: interaction)

      assert_equal [:send, :ast_deferred, :send, :ast_deferred_call], reordered.map(&:type)
      assert_same setup_statement, reordered[0]
      assert_same interaction, reordered[2]
      assert_same reordered[1].children[0], reordered[3].children[0]
    end

    test "run_after supports after: textually before the run (pure sink)" do
      first, second, third = parse("first\nsecond\nthird\n").children

      reordered = run_after([first, second, third], run: [third], after: first)

      assert_equal [:send, :ast_deferred_call, :send, :ast_deferred], reordered.map(&:type)
    end

    test "run_after matches statements by identity, not equality" do
      # Two textually identical statements: value matching would be ambiguous.
      first, duplicate_of_first, last = parse("foo\nfoo\nbar\n").children

      reordered = run_after([first, duplicate_of_first, last], run: [duplicate_of_first], after: last)

      assert_same first, reordered[0]
      assert_equal :ast_deferred, reordered[1].type
      assert_same last, reordered[2]
    end

    test "run_after rejects a non-contiguous run" do
      first, second, third = parse("first\nsecond\nthird\n").children

      assert_raises(ArgumentError) { run_after([first, second, third], run: [first, third], after: second) }
    end

    test "run_after rejects after: inside the run" do
      first, second, third = parse("first\nsecond\nthird\n").children

      assert_raises(ArgumentError) { run_after([first, second, third], run: [first, second], after: second) }
    end

    test "run_after rejects statements not in the sequence" do
      first, second = parse("first\nsecond\n").children
      foreign = s(:send, nil, :foreign)

      assert_raises(ArgumentError) { run_after([first, second], run: [foreign], after: second) }
      assert_raises(ArgumentError) { run_after([first, second], run: [first], after: foreign) }
    end
  end
end

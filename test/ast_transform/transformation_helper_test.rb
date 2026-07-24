# frozen_string_literal: true

require 'test_helper'
require 'ast_transform/transformation_helper'
require 'ast_transform/abstract_transformation'
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

    test "s_at raises TransformationHelper::MissingLocationError for loc-less anchors" do
      error = assert_raises(TransformationHelper::MissingLocationError) { s_at(s(:send, nil, :foo), :send, nil, :bar) }

      assert_includes error.message, 'send'
    end

    test "thunk builds a Thunk node carrying an internal id and the body" do
      statements = parse("foo\nbar\n").children

      node = thunk(*statements)

      assert_instance_of Thunk, node
      assert_equal :ast_thunk, node.type
      assert_instance_of Thunk::Id, node.id
      assert_equal statements, node.body
    end

    test "a Thunk without an id cannot be constructed" do
      error = assert_raises(ArgumentError) { s(:ast_thunk, parse("foo\n")) }

      assert_includes error.message, 'Thunk::Id'
    end

    test "a Thunk with an empty body cannot be constructed" do
      error = assert_raises(ArgumentError) { thunk }

      assert_includes error.message, 'at least one statement'
    end

    test "a Processor rebuild preserves the Thunk class, id, and invariants" do
      node = thunk(parse("foo\n"))

      rebuilt = node.updated(nil, [node.id, parse("bar\n")])

      assert_instance_of Thunk, rebuilt
      assert_same node.id, rebuilt.id
      assert_raises(ArgumentError) { node.updated(nil, [node.id]) }
    end

    test "AbstractTransformation descends thunk bodies by default" do
      swap_foo_for_bar = Class.new(AbstractTransformation) do
        def on_send(node)
          node.children[1] == :foo ? node.updated(nil, [node.children[0], :bar]) : node
        end
      end
      node = thunk(parse("foo\n"))

      processed = swap_foo_for_bar.new.run(node)

      assert_instance_of Thunk, processed
      assert_same node.id, processed.id
      assert_equal :bar, processed.body[0].children[1]
    end

    test "thunk imposes no control-flow validation (semantics are the proc lowering's contract)" do
      # return is transparent through the non-lambda proc; severed jumps keep
      # Ruby's native behavior (see ThunkLowering / LineAlignedEmitterTest).
      assert_instance_of Thunk, thunk(parse("return 1 if early\n"))
      assert_instance_of Thunk, thunk(parse("break\n"))
    end

    test "run_after removes the run and inserts a thunk after the anchor" do
      setup_statement, when_statement, interaction = parse("given\nwhen_body\ninteraction\n").children

      reordered = run_after([setup_statement, when_statement, interaction], run: [when_statement], after: interaction)

      assert_equal [:send, :send, :ast_thunk], reordered.map(&:type)
      assert_same setup_statement, reordered[0]
      assert_same interaction, reordered[1]
      assert_equal [when_statement], reordered[2].body
    end

    test "run_after matches statements by identity, not equality" do
      # Two textually identical statements: value matching would be ambiguous.
      first, duplicate_of_first, last = parse("foo\nfoo\nbar\n").children

      reordered = run_after([first, duplicate_of_first, last], run: [duplicate_of_first], after: last)

      assert_same first, reordered[0]
      assert_same last, reordered[1]
      assert_equal :ast_thunk, reordered[2].type
      assert_same duplicate_of_first, reordered[2].body[0]
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

# frozen_string_literal: true

require 'test_helper'
require 'ast_transform/kwargs_builder'

module ASTTransform
  class KwargsBuilderTest < Minitest::Test
    extend ASTTransform::Declarative

    def setup
      @builder = ASTTransform::KwargsBuilder.new
      @parser = Prism::Translation::Parser.new(@builder)
    end

    test "#associate emits :kwargs for bare keyword arguments" do
      ast = parse('foo(bar: 1, baz: 2)')
      node = find_node(ast, :kwargs)

      refute_nil node, "expected a :kwargs node for bare keyword arguments"
      assert_equal :kwargs, node.type
    end

    test "#associate emits :hash for explicit hash with braces" do
      ast = parse('foo({ bar: 1, baz: 2 })')
      hash_node = find_node(ast, :hash)

      refute_nil hash_node, "expected a :hash node for explicit hash"
      assert_equal :hash, hash_node.type
      assert_nil find_node(ast, :kwargs)
    end

    test "#associate emits :kwargs for keyword arguments mixed with positional arguments" do
      ast = parse('foo("hello", bar: 1)')
      node = find_node(ast, :kwargs)

      refute_nil node, "expected a :kwargs node for keyword arguments"
      assert_equal :kwargs, node.type
    end

    test "#associate emits :hash for standalone hash literals" do
      ast = parse('x = { a: 1, b: 2 }')
      hash_node = find_node(ast, :hash)

      refute_nil hash_node, "expected a :hash node for hash literal"
      assert_equal :hash, hash_node.type
      assert_nil find_node(ast, :kwargs)
    end

    test "#associate preserves keyword argument pairs" do
      ast = parse('foo(bar: 1, baz: 2)')
      node = find_node(ast, :kwargs)

      assert_equal 2, node.children.length
      assert_equal :pair, node.children[0].type
      assert_equal :pair, node.children[1].type

      assert_equal :bar, node.children[0].children[0].children[0]
      assert_equal :baz, node.children[1].children[0].children[0]
    end

    test "#associate emits :kwargs for keyword arguments in constructor calls" do
      ast = parse('Foo.new(bar: 1, baz: 2)')
      node = find_node(ast, :kwargs)

      refute_nil node, "expected a :kwargs node in constructor call"
      assert_equal :kwargs, node.type
    end

    test "#associate emits :kwargs for double-splat keyword arguments" do
      ast = parse('foo(**opts)')
      node = find_node(ast, :kwargs)

      refute_nil node, "expected a :kwargs node for double-splat"
    end

    private

    def parse(source)
      buffer = Parser::Source::Buffer.new('test')
      buffer.source = source
      @parser.parse(buffer)
    end

    def find_node(ast, type)
      return ast if ast.type == type
      return nil unless ast.respond_to?(:children)

      ast.children.each do |child|
        next unless child.is_a?(Parser::AST::Node)

        found = find_node(child, type)
        return found if found
      end

      nil
    end
  end
end

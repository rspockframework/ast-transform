# frozen_string_literal: true

require "test_helper"
require "ast_transform/transformation_helper"
require "ast_transform/modern_builder"

module ASTTransform
  class ModernBuilderTest < Minitest::Test
    extend ASTTransform::Declarative
    include ASTTransform::TransformationHelper

    def setup
      @builder = ASTTransform::ModernBuilder.new
      @parser = Prism::Translation::Parser.new(@builder)
    end

    MODERNIZE_FLAGS = [
      :emit_lambda,
      :emit_procarg0,
      :emit_encoding,
      :emit_index,
      :emit_arg_inside_procarg0,
      :emit_forward_arg,
      :emit_kwargs,
      :emit_match_pattern,
    ].freeze

    test "opts into every modernize flag" do
      MODERNIZE_FLAGS.each do |flag|
        assert ASTTransform::ModernBuilder.public_send(flag), "expected #{flag} to be on"
      end
    end

    test "leaves the global default builder's flags untouched" do
      MODERNIZE_FLAGS.each do |flag|
        refute Parser::Builders::Default.public_send(flag), "expected #{flag} to stay off on the global default"
      end
    end

    test "#args wraps a lone block parameter in :procarg0 (non-splatting `|a|`)" do
      block_args = find_node(parse("x { |a| a }"), :args)

      # Legacy shape s(:args, s(:arg, :a)) means the trailing-comma form `|a,|` to Unparser, which auto-splats.
      assert_equal s(:args, s(:procarg0, s(:arg, :a))), block_args
    end

    test "#args keeps the trailing-comma block parameter as a bare :arg" do
      block_args = find_node(parse("x { |a,| a }"), :args)

      assert_equal s(:args, s(:arg, :a)), block_args
    end

    test "#args nests destructured block parameters inside :procarg0" do
      block_args = find_node(parse("x { |(a, b)| a }"), :args)

      assert_equal s(:args, s(:procarg0, s(:arg, :a), s(:arg, :b))), block_args
    end

    test "#args leaves multi-parameter blocks as bare :arg nodes" do
      block_args = find_node(parse("x { |a, b| a }"), :args)

      assert_equal s(:args, s(:arg, :a), s(:arg, :b)), block_args
    end

    test "#block emits :lambda for the stabby lambda literal" do
      # No :procarg0 here: lambda arity is strict, so a lone parameter never auto-splats.
      assert_equal s(:block, s(:lambda), s(:args, s(:arg, :a)), s(:lvar, :a)), parse("->(a) { a }")
    end

    test "#index emits :index for subscript access" do
      assert_equal s(:index, s(:send, nil, :foo), s(:int, 1)), parse("foo[1]")
    end

    test "#index_asgn emits :indexasgn for subscript assignment" do
      assert_equal s(:indexasgn, s(:send, nil, :foo), s(:int, 1), s(:int, 2)), parse("foo[1] = 2")
    end

    test "#forward_arg emits :forward_arg inside :args for a forwarding def" do
      def_args = parse("def m(...) = n(...)").children[1]

      # The legacy shape replaces :args wholesale with :forward_args, which Unparser does not emit as `(...)`.
      assert_equal s(:args, s(:forward_arg)), def_args
    end

    test "#__ENCODING__ emits :__ENCODING__" do
      assert_equal s(:__ENCODING__), parse("__ENCODING__")
    end

    test "#match_pattern emits :match_pattern for rightward assignment" do
      assert_equal s(:match_pattern, s(:send, nil, :x), s(:match_var, :a)), parse("x => a")
    end

    test "#match_pattern_p emits :match_pattern_p for the `in` predicate" do
      assert_equal s(:match_pattern_p, s(:send, nil, :x), s(:match_var, :a)), parse("x in a")
    end

    test "#associate emits :kwargs for bare keyword arguments" do
      ast = parse("foo(bar: 1, baz: 2)")
      node = find_node(ast, :kwargs)

      refute_nil node, "expected a :kwargs node for bare keyword arguments"
      assert_equal :kwargs, node.type
    end

    test "#associate emits :hash for explicit hash with braces" do
      ast = parse("foo({ bar: 1, baz: 2 })")
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
      ast = parse("x = { a: 1, b: 2 }")
      hash_node = find_node(ast, :hash)

      refute_nil hash_node, "expected a :hash node for hash literal"
      assert_equal :hash, hash_node.type
      assert_nil find_node(ast, :kwargs)
    end

    test "#associate preserves keyword argument pairs" do
      ast = parse("foo(bar: 1, baz: 2)")
      node = find_node(ast, :kwargs)

      assert_equal 2, node.children.length
      assert_equal :pair, node.children[0].type
      assert_equal :pair, node.children[1].type

      assert_equal :bar, node.children[0].children[0].children[0]
      assert_equal :baz, node.children[1].children[0].children[0]
    end

    test "#associate emits :kwargs for keyword arguments in constructor calls" do
      ast = parse("Foo.new(bar: 1, baz: 2)")
      node = find_node(ast, :kwargs)

      refute_nil node, "expected a :kwargs node in constructor call"
      assert_equal :kwargs, node.type
    end

    test "#associate emits :kwargs for double-splat keyword arguments" do
      ast = parse("foo(**opts)")
      node = find_node(ast, :kwargs)

      refute_nil node, "expected a :kwargs node for double-splat"
    end

    private

    def parse(source)
      buffer = Parser::Source::Buffer.new("test")
      buffer.source = source
      @parser.parse(buffer)
    end

    def find_node(ast, type)
      return ast if ast.type == type
      return unless ast.respond_to?(:children)

      ast.children.each do |child|
        next unless child.is_a?(Parser::AST::Node)

        found = find_node(child, type)
        return found if found
      end

      nil
    end
  end
end

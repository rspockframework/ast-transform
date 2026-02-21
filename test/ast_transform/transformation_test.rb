# frozen_string_literal: true
require 'test_helper'
require 'transformation_helper'
require 'ast_transform/transformation'

module ASTTransform
  class TransformationTest < Minitest::Test
    extend ASTTransform::Declarative
    include ASTTransform::Helpers::TransformationHelper

    class FooTransformation < ASTTransform::AbstractTransformation
      private

      def process_node(node)
        node.updated(:send, [nil, :foo])
      end
    end

    class ClassNamePrefixerTransformation < ASTTransform::AbstractTransformation
      private

      def process_node(node)
        return node unless node.type == :class

        process_class_node(node)
      end

      def process_class_node(node)
        children = node.children.dup
        children[0] = children[0].updated(nil, [nil, "Prefix#{node.children[0].children[1]}".to_sym])

        node.updated(nil, children)
      end
    end

    def setup
      @transformation = ASTTransform::Transformation.new
    end

    test "transform! is not considered an annotation if on its own in a file" do
      source = <<~HEREDOC
        transform!(FooTransformation)
      HEREDOC

      expected = "transform!(FooTransformation)"

      assert_equal expected, transform(source, @transformation)
    end

    test "transform! is not considered an annotation if it does not annotate anything" do
      source = <<~HEREDOC
        class Potato
        end
        transform!(FooTransformation)
      HEREDOC

      expected = <<~HEREDOC
        class Potato
        end
        transform!(FooTransformation)
      HEREDOC

      assert_equal expected, transform(source, @transformation)
    end

    test "transform! is not considered an annotation if it does not have arguments" do
      source = <<~HEREDOC
        transform!
        class Potato
        end
      HEREDOC

      expected = <<~HEREDOC
        transform!

        class Potato
        end
      HEREDOC

      assert_equal expected, transform(source, @transformation)
    end

    test "transform! runs the transformation if annotating a Class node" do
      source = <<~HEREDOC
        transform!(ASTTransform::TransformationTest::FooTransformation)
        class Potato
        end
      HEREDOC

      expected = "foo"

      assert_equal expected, transform(source, @transformation)
    end

    test "multiple transform! on the same level each run their transformation" do
      source = <<~HEREDOC
        transform!(ASTTransform::TransformationTest::FooTransformation)
        class Potato
        end

        transform!(ASTTransform::TransformationTest::FooTransformation)
        class Potato
        end
      HEREDOC

      expected = <<~HEREDOC
        foo
        foo
      HEREDOC

      assert_equal expected, transform(source, @transformation)
    end

    test "nested transform! each run their transformation" do
      source = <<~HEREDOC
        transform!(ASTTransform::TransformationTest::ClassNamePrefixerTransformation)
        class Foo
          transform!(ASTTransform::TransformationTest::FooTransformation)
          class Bar
          end
        end
      HEREDOC

      expected = <<~HEREDOC
        class PrefixFoo
          foo
        end
      HEREDOC

      assert_equal expected, transform(source, @transformation)
    end

    test "transform! will run the transformation on the following node only" do
      source = <<~HEREDOC
        transform!(ASTTransform::TransformationTest::ClassNamePrefixerTransformation)
        class Foo
          class Bar
          end
        end
      HEREDOC

      expected = <<~HEREDOC
        class PrefixFoo
          class Bar
          end
        end
      HEREDOC

      assert_equal expected, transform(source, @transformation)
    end

    test "begin node is preserved when no transform! annotations are present" do
      source = <<~HEREDOC
        class Foo
        end

        class Bar
        end
      HEREDOC

      expected = <<~HEREDOC
        class Foo
        end

        class Bar
        end
      HEREDOC

      assert_equal expected, transform(source, @transformation)
    end

    test "begin node is preserved when non-transformable siblings remain after transform! removal" do
      source = <<~HEREDOC
        transform!(ASTTransform::TransformationTest::FooTransformation)
        class Potato
        end

        class Bar
        end
      HEREDOC

      expected = <<~HEREDOC
        foo

        class Bar
        end
      HEREDOC

      assert_equal expected, transform(source, @transformation)
    end

    test "transform! runs the transformation on a constant assignment node" do
      source = <<~HEREDOC
        transform!(ASTTransform::TransformationTest::FooTransformation)
        Potato = Class.new do
        end
      HEREDOC

      expected = "foo"

      assert_equal expected, transform(source, @transformation)
    end
  end
end

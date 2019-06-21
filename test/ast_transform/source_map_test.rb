# frozen_string_literal: true
require 'test_helper'
require 'transformation_helper'
require 'ast_transform/abstract_transformation'
require 'ast_transform/transformer'

module ASTTransform
  class SourceMapTest < Minitest::Test
    extend ASTTransform::Declarative
    include ASTTransform::Helpers::TransformationHelper

    test "#line returns the correct line number when transformation wraps node in a virtual node" do
      transformation = Class.new(ASTTransform::AbstractTransformation) do
        def run(node)
          s(:send, node, :+, s(:int, 1))
        end
      end.new

      transformer = ASTTransform::Transformer.new(transformation)

      source = <<~HEREDOC
        method_call
      HEREDOC

      expected_transformed_source = <<~HEREDOC
        method_call + 1
      HEREDOC

      actual_transformed_source = transformer.transform_file_source(source, 'src', 'transformed')

      assert_equal strip_end_line(expected_transformed_source), actual_transformed_source

      source_map = ASTTransform::SourceMap.for_file_path('transformed')

      assert_equal 1, source_map.line(1)
    end

    test "#line returns the correct line number when transformation updates node" do
      transformation = Class.new(ASTTransform::AbstractTransformation) do
        def run(node)
          node.updated(:send, [node, :+, s(:int, 1)])
        end
      end.new

      transformer = ASTTransform::Transformer.new(transformation)

      source = <<~HEREDOC
        method_call
      HEREDOC

      expected_transformed_source = <<~HEREDOC
        method_call + 1
      HEREDOC

      actual_transformed_source = transformer.transform_file_source(source, 'src', 'transformed')

      assert_equal strip_end_line(expected_transformed_source), actual_transformed_source

      transformer.transform_file_source(source, 'src', 'transformed')
      source_map = ASTTransform::SourceMap.for_file_path('transformed')

      assert_equal 1, source_map.line(1)
    end

    test "#line returns the correct line number when transformation makes code collapse on the same line" do
      transformation = Class.new(ASTTransform::AbstractTransformation) do
        def run(node)
          s(:send, node.children[0], :+, node.children[1])
        end
      end.new

      transformer = ASTTransform::Transformer.new(transformation)

      source = <<~HEREDOC
        method_call1
        method_call2
      HEREDOC

      expected_transformed_source = <<~HEREDOC
        method_call1 + method_call2
      HEREDOC

      actual_transformed_source = transformer.transform_file_source(source, 'src', 'transformed')

      assert_equal strip_end_line(expected_transformed_source), actual_transformed_source

      source_map = ASTTransform::SourceMap.for_file_path('transformed')

      assert_equal 1, source_map.line(1)
    end

    test "#line returns the correct line number when transformation makes code expand on multiple lines" do
      transformation = Class.new(ASTTransform::AbstractTransformation) do
        def run(node)
          node.updated(:begin, [node.children[0], node.children[2]])
        end
      end.new

      transformer = ASTTransform::Transformer.new(transformation)

      source = <<~HEREDOC
        method_call1 + method_call2
      HEREDOC

      expected_transformed_source = <<~HEREDOC
        method_call1
        method_call2
      HEREDOC

      actual_transformed_source = transformer.transform_file_source(source, 'src', 'transformed')

      assert_equal strip_end_line(expected_transformed_source), actual_transformed_source

      source_map = ASTTransform::SourceMap.for_file_path('transformed')

      assert_equal 1, source_map.line(1)
      assert_equal 1, source_map.line(2)
    end

    test "#line returns nil when transformation creates nodes that don't contain previous nodes" do
      transformation = Class.new(ASTTransform::AbstractTransformation) do
        def run(node)
          s(:send, s(:int, 1), :+, s(:int, 2))
        end
      end.new

      transformer = ASTTransform::Transformer.new(transformation)

      source = <<~HEREDOC
        method_call1 + method_call2
      HEREDOC

      expected_transformed_source = <<~HEREDOC
        1 + 2
      HEREDOC

      actual_transformed_source = transformer.transform_file_source(source, 'src', 'transformed')

      assert_equal strip_end_line(expected_transformed_source), actual_transformed_source

      source_map = ASTTransform::SourceMap.for_file_path('transformed')

      assert_nil source_map.line(1)
    end
  end
end

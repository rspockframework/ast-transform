# frozen_string_literal: true

require "tmpdir"
require "test_helper"
require "transformation_helper"
require "ast_transform/source_parser"

module ASTTransform
  class SourceParserTest < Minitest::Test
    extend ASTTransform::Declarative
    include ASTTransform::Helpers::TransformationHelper

    def setup
      @source_parser = ASTTransform::SourceParser.new
    end

    test "#parse returns the expected AST" do
      assert_equal s(:send, nil, :method_call), @source_parser.parse("method_call")
    end

    test "#parse records the file path on source locations" do
      ast = @source_parser.parse("method_call", file_path: "some/file.rb")

      assert_equal "some/file.rb", ast.loc.expression.source_buffer.name
    end

    test "#parse can be called repeatedly on one instance" do
      assert_equal s(:send, nil, :first), @source_parser.parse("first")
      assert_equal s(:send, nil, :second), @source_parser.parse("second")
    end

    test "#parse_file parses the file's source and records its path" do
      Dir.mktmpdir do |dir|
        file_path = File.join(dir, "input.rb")
        File.write(file_path, "method_call\n")

        ast = @source_parser.parse_file(file_path)

        assert_equal s(:send, nil, :method_call), ast
        assert_equal file_path, ast.loc.expression.source_buffer.name
      end
    end

    test "ASTTransform.parse parses through the shared seam" do
      assert_equal s(:send, nil, :method_call), ASTTransform.parse("method_call")
    end

    test "ASTTransform.parse_file parses the file's source" do
      Dir.mktmpdir do |dir|
        file_path = File.join(dir, "input.rb")
        File.write(file_path, "method_call\n")

        assert_equal s(:send, nil, :method_call), ASTTransform.parse_file(file_path)
      end
    end
  end
end

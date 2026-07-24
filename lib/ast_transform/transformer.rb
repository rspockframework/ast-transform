# frozen_string_literal: true

require 'prism'
require 'prism/translation/parser'
require 'unparser'
require 'ast_transform/kwargs_builder'
require 'ast_transform/line_aligned_emitter'

module ASTTransform
  class Transformer
    # Constructs a new Transformer instance.
    #
    # @param transformations [Array<ASTTransform::AbstractTransformation>] The transformations to be run.
    def initialize(*transformations)
      @transformations = transformations
    end

    # Builds the AST for the given +source+.
    #
    # @param source [String] The input source code.
    # @param file_path [String] The file_path. This is important for source mapping in backtraces.
    #
    # @return [Parser::AST::Node] The AST.
    def build_ast(source, file_path: "tmp")
      buffer = create_buffer(source, file_path)
      parser.parse(buffer)
    end

    # Builds the AST for the given +file_path+.
    #
    # @param file_path [String] The input file path.
    #
    # @return [Parser::AST::Node] The AST.
    def build_ast_from_file(file_path)
      source = File.read(file_path)
      build_ast(source, file_path: file_path)
    end

    # Transforms the given +source+.
    #
    # @param source [String] The input source code to be transformed.
    #
    # @return [String] The transformed code, line-aligned (see #transform_file_source).
    def transform(source)
      ast = build_ast(source)
      transformed_ast = transform_ast(ast)
      LineAlignedEmitter.new(transformed_ast, 'tmp').emit
    end

    # Transforms the give +file_path+.
    #
    # @param file_path [String] The input file to be transformed. Statement placement (and therefore
    # backtrace and breakpoint line numbers) is derived from this file's source locations.
    # @param transformed_file_path [String] The file path to the transformed file.
    #
    # @return [String] The transformed code.
    def transform_file(file_path, transformed_file_path)
      source = File.read(file_path)
      transform_file_source(source, file_path, transformed_file_path)
    end

    # Transforms the given +source+ in +file_path+.
    #
    # @param source [String] The input source code to be transformed.
    # @param file_path [String] The file path for the input +source+. Statement placement (and
    # therefore backtrace and breakpoint line numbers) is derived from the source locations parsed
    # under this path.
    # @param transformed_file_path [String] The file path the transformed file will be written to.
    #
    # @return [String] The transformed code, line-aligned: every statement carrying a source
    # location is emitted at its original source line.
    def transform_file_source(source, file_path, _transformed_file_path)
      source_ast = build_ast(source, file_path: file_path)
      # At this point, the transformed_ast contains source locations for the original +source+.
      transformed_ast = transform_ast(source_ast)

      LineAlignedEmitter.new(transformed_ast, file_path).emit
    end

    # Transforms the given +ast+.
    #
    # @param ast [Parser::AST::Node] The input AST to be transformed.
    #
    # @return [Parser::AST::Node] The transformed AST.
    def transform_ast(ast)
      @transformations.inject(ast) do |ast, transformation|
        transformation.run(ast)
      end
    end

    private

    def create_buffer(source, file_path)
      buffer = Parser::Source::Buffer.new(file_path)
      buffer.source = source.dup.force_encoding(parser.default_encoding)

      buffer
    end

    def parser
      @parser&.reset
      @parser ||= Prism::Translation::Parser.new(ASTTransform::KwargsBuilder.new)
    end
  end
end

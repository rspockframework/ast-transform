# frozen_string_literal: true

require "prism"
require "prism/translation/parser"
require "ast_transform/kwargs_builder"

module ASTTransform
  # Owns source → AST parsing: Prism's C parser through its whitequark translation layer, so every consumer gets the
  # node vocabulary Parser::AST::Processor understands. Transformer parses through this seam; analysis-only
  # consumers that never emit instantiate it directly and keep the instance for as many parses as they need.
  class SourceParser
    # Parses the given +source+.
    #
    # @param source [String] The input source code.
    # @param file_path [String] The file path recorded on source locations. This is important for source mapping
    # in backtraces.
    #
    # @return [Parser::AST::Node] The AST.
    def parse(source, file_path: "tmp")
      buffer = create_buffer(source, file_path)
      parser.parse(buffer)
    end

    # Parses the source in the given +file_path+.
    #
    # @param file_path [String] The input file path.
    #
    # @return [Parser::AST::Node] The AST.
    def parse_file(file_path)
      parse(File.read(file_path), file_path: file_path)
    end

    private

    # Builds a source buffer over +source+ in the parser's default encoding.
    #
    # @param source [String] The input source code.
    # @param file_path [String] The file path recorded on the buffer.
    #
    # @return [Parser::Source::Buffer] The buffer.
    def create_buffer(source, file_path)
      buffer = Parser::Source::Buffer.new(file_path)
      buffer.source = source.dup.force_encoding(parser.default_encoding)

      buffer
    end

    # The memoized parser, reset between parses.
    #
    # @return [Prism::Translation::Parser] The parser.
    def parser
      @parser&.reset
      @parser ||= Prism::Translation::Parser.new(ASTTransform::KwargsBuilder.new)
    end
  end
end

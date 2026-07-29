# frozen_string_literal: true

require "prism"
require "prism/translation/parser"
require "ast_transform/kwargs_builder"

module ASTTransform
  # Owns source → AST parsing: Prism's C parser through its whitequark translation layer, so every consumer gets the
  # node vocabulary Parser::AST::Processor understands. Transformer parses through this seam; analysis-only
  # consumers that never emit instantiate it directly and keep the instance for as many parses as they need.
  class SourceParser
    # Constructs a new SourceParser instance.
    #
    # KwargsBuilder is a required implementation detail, not an injection seam: the framework's emission depends
    # on the kwargs/hash distinction it preserves, so every parse goes through it.
    def initialize
      @builder = KwargsBuilder.new
    end

    # Parses the given +source+.
    #
    # @param source [String] The input source code.
    # @param file_path [String] The file path recorded on source locations. This is important for source mapping
    # in backtraces.
    #
    # @return [Parser::AST::Node] The AST.
    def parse(source, file_path: "tmp")
      # A fresh parser per parse: parser instances accumulate per-run state (lexer position, diagnostics), and
      # constructing one is trivial next to the parse itself.
      parser = Prism::Translation::Parser.new(@builder)
      parser.parse(create_buffer(source, file_path, parser.default_encoding))
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

    # Builds a source buffer over +source+ in the given +encoding+.
    #
    # @param source [String] The input source code.
    # @param file_path [String] The file path recorded on the buffer.
    # @param encoding [Encoding] The encoding the buffer's source is coerced to.
    #
    # @return [Parser::Source::Buffer] The buffer.
    def create_buffer(source, file_path, encoding)
      buffer = Parser::Source::Buffer.new(file_path)
      buffer.source = source.dup.force_encoding(encoding)

      buffer
    end
  end
end

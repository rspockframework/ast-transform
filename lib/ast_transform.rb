# frozen_string_literal: true

require "ast_transform/version"
require "ast_transform/instruction_sequence"
require "ast_transform/instruction_sequence/mixin"
require "ast_transform/instruction_sequence/bootsnap_mixin"
require "ast_transform/source_parser"

module ASTTransform
  DEFAULT_OUTPUT_PATH = Pathname.new("").join("tmp", "ast_transform").to_s

  class << self
    # Parses the given +source+ into the framework's AST vocabulary. The entry point for analysis-only consumers
    # that never emit (see ASTTransform::AbstractAnalysis); transformation pipelines go through Transformer.
    #
    # @param source [String] The input source code.
    # @param file_path [String] The file path recorded on source locations.
    #
    # @return [Parser::AST::Node] The AST.
    def parse(source, file_path: "tmp")
      source_parser.parse(source, file_path: file_path)
    end

    # Parses the source in the given +file_path+ (see .parse).
    #
    # @param file_path [String] The input file path.
    #
    # @return [Parser::AST::Node] The AST.
    def parse_file(file_path)
      source_parser.parse_file(file_path)
    end

    def acronyms
      @acronyms ||= []
    end

    def acronym(acronym)
      acronyms << acronym
      acronyms.uniq!
    end

    def install
      @installed ||= if defined?(Bootsnap) && ASTTransform::InstructionSequence.using_bootsnap_compilation?
        class << Bootsnap::CompileCache::ISeq
          prepend ::ASTTransform::InstructionSequence::BootsnapMixin
        end
      else
        class << RubyVM::InstructionSequence
          prepend ::ASTTransform::InstructionSequence::Mixin
        end
      end
    end

    attr_writer :output_path

    def output_path
      @output_path || DEFAULT_OUTPUT_PATH
    end

    private

    def source_parser
      @source_parser ||= SourceParser.new
    end
  end
end

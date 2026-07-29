# frozen_string_literal: true

require "ast_transform/version"
require "ast_transform/instruction_sequence"
require "ast_transform/instruction_sequence/mixin"
require "ast_transform/instruction_sequence/bootsnap_mixin"
require "ast_transform/source_parser"

module ASTTransform
  DEFAULT_OUTPUT_PATH = Pathname.new("").join("tmp", "ast_transform").to_s

  class << self
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
  end
end

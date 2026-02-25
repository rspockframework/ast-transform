# frozen_string_literal: true
require 'pathname'
require 'ast_transform/transformer'
require 'ast_transform/transformation'
require 'ast_transform/instruction_sequence/mixin_utils'

module ASTTransform
  module InstructionSequence
    module Mixin
      def load_iseq(source_path)
        return ASTTransform::MixinUtils.try_super(self, :load_iseq, source_path) if source_path == __FILE__

        # Binary read avoids encoding errors during the fast-path check below.
        # Downstream (Prism, RubyVM::InstructionSequence) handle encoding natively
        # via magic comments, so we never need to set it ourselves.
        source = File.binread(source_path)

        return ASTTransform::MixinUtils.try_super(self, :load_iseq, source_path) unless source.include?('transform!'.b)

        ASTTransform::InstructionSequence.source_to_transformed_iseq(source, source_path)
      end
    end
  end
end

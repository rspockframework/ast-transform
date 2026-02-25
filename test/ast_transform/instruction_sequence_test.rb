# frozen_string_literal: true

require 'test_helper'
require 'tempfile'
require 'ast_transform/instruction_sequence'
require 'ast_transform/instruction_sequence/mixin'
require 'ast_transform/transformation'

module ASTTransform
  class InstructionSequenceTest < Minitest::Test
    extend ASTTransform::Declarative

    class ClassWithMixin
      include ASTTransform::InstructionSequence::Mixin
    end

    def setup
      @loader = ClassWithMixin.new
    end

    test "compiled iseq reports original source path" do
      source = "1 + 2\n"
      source_path = File.expand_path("test/fixtures/dummy.rb")

      iseq = ASTTransform::InstructionSequence.source_to_transformed_iseq(source, source_path)

      assert_equal source_path, iseq.path,
        "ISeq should report the original source path, not the tmp/ rewritten path"
    end

    test "source_to_transformed_iseq handles binary-encoded source" do
      source = "# café résumé\n1 + 2\n".dup.force_encoding('ASCII-8BIT')
      source_path = File.expand_path("test/fixtures/encoding_test.rb")

      iseq = ASTTransform::InstructionSequence.source_to_transformed_iseq(source, source_path)

      assert_equal source_path, iseq.path
    end

    test "load_iseq skips non-ASCII files without transform!" do
      tmpfile = Tempfile.new(['non_ascii', '.rb'])
      tmpfile.write("# café résumé\nx = 1\n")
      tmpfile.close

      iseq = @loader.load_iseq(tmpfile.path)

      assert_nil iseq
    ensure
      tmpfile&.unlink
    end

    test "load_iseq processes non-ASCII files with transform! without encoding errors" do
      tmpfile = Tempfile.new(['non_ascii_transform', '.rb'])
      tmpfile.write("# café résumé\nx = 1\n# transform!\n")
      tmpfile.close

      iseq = @loader.load_iseq(tmpfile.path)

      assert_instance_of RubyVM::InstructionSequence, iseq
      assert_equal tmpfile.path, iseq.path
    ensure
      tmpfile&.unlink
    end
  end
end

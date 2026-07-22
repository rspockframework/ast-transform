# frozen_string_literal: true
require 'test_helper'
require 'transformation_helper'
require 'ast_transform/instruction_sequence'
require 'ast_transform/transformation'
require 'ast_transform/transformer'

module ASTTransform
  # Acceptance tests for line-aligned emission: every user statement must be
  # emitted at its original source line, so that backtraces, debuggers and
  # breakpoints are correct by construction — with no mapping or filtering.
  class LineAlignmentTest < Minitest::Test
    extend ASTTransform::Declarative
    include ASTTransform::Helpers::TransformationHelper

    # Injects a synthetic (loc-less) statement at the start of every method
    # body. Represents transforms that add code: synthetic statements have no
    # source-line truth, so they must never push user statements off their
    # source lines.
    class SetupInjectionTransformation < ASTTransform::AbstractTransformation
      private

      def process_node(node)
        # :defs is `def self.name`; its body sits one child later than :def's.
        return method(:process).super_method.call(node) unless [:def, :defs].include?(node.type)

        *prefix, body = node.children
        injected_setup = s(:send, nil, :injected_setup)
        node.updated(nil, [*prefix, s(:begin, injected_setup, *Array(body))])
      end
    end

    # Source layout chosen so Unparser's fresh formatting diverges from it:
    # blank lines, comments and a multi-line expression shift all following
    # statements when the layout is regenerated naively. The gaps are wide
    # enough that no naive layout can land the statements on their source
    # lines by coincidence.
    FIXTURE_SOURCE = <<~HEREDOC
      class LineAlignmentFixture
        def self.compute
          first_value = 1

          # An explanatory comment: comments vanish from the AST, so a naive
          # unparse pulls everything below this line upward.

          second_value = first_value +
            1

          raise_helper(second_value)
        end
      end
    HEREDOC

    FIXTURE_LINES = {
      'first_value = 1' => 3,
      'second_value = first_value' => 8,
      'raise_helper(second_value)' => 11,
    }.freeze

    test "emission places each user statement at its source line" do
      emitted = transform_file_source(FIXTURE_SOURCE, ASTTransform::Transformation.new)

      FIXTURE_LINES.each do |statement, source_line|
        assert_equal source_line, emitted_line_number(emitted, statement),
          "expected `#{statement}` at source line #{source_line} in:\n#{numbered(emitted)}"
      end
    end

    test "emission keeps user statements on their source lines when a transform injects synthetic code" do
      emitted = transform_file_source(FIXTURE_SOURCE, SetupInjectionTransformation.new)

      assert_includes emitted, 'injected_setup'
      FIXTURE_LINES.each do |statement, source_line|
        assert_equal source_line, emitted_line_number(emitted, statement),
          "expected `#{statement}` at source line #{source_line} in:\n#{numbered(emitted)}"
      end
    end

    test "raw backtrace cites the source line of the raising statement, with no filtering" do
      source = <<~HEREDOC
        class LineAlignmentRaiseFixture
          def self.boom
            value = 1

            # Comments and blank lines force the naive unparse layout to
            # diverge from the source layout.

            raise "boom" if value == 1
          end
        end
      HEREDOC
      raise_line = 8

      iseq = compile(source, 'line_alignment_raise_fixture.rb')
      iseq.eval

      error = assert_raises(RuntimeError) { LineAlignmentRaiseFixture.boom }

      assert_equal raise_line, error.backtrace_locations.first.lineno,
        "raw backtrace (no SourceMap, no filter) should cite the source line of the raise"
    ensure
      Object.send(:remove_const, :LineAlignmentRaiseFixture) if Object.const_defined?(:LineAlignmentRaiseFixture)
    end

    test "compiled iseq line table contains the source lines of user statements" do
      iseq = compile(FIXTURE_SOURCE, 'line_alignment_fixture.rb')

      lines = iseq_lines(iseq)

      FIXTURE_LINES.each do |statement, source_line|
        assert_includes lines, source_line,
          "a breakpoint on source line #{source_line} (`#{statement}`) should be able to bind; " \
            "line table: #{lines.sort.uniq}"
      end
    end

    private

    def transform_file_source(source, *transformations)
      source_pathname = tmp_pathname('line_alignment_source.rb')
      transformed_pathname = tmp_pathname('line_alignment_transformed.rb')

      ASTTransform::Transformer.new(*transformations)
        .transform_file_source(source, source_pathname.to_s, transformed_pathname.to_s)
    end

    def compile(source, file_name)
      ASTTransform::InstructionSequence.source_to_transformed_iseq(source, tmp_pathname(file_name).to_s)
    end

    def tmp_pathname(file_name)
      Pathname.new('').join(File.expand_path(''), 'tmp', 'test', 'ast_transform', file_name)
    end

    # 1-based line number of the first emitted line containing +statement+.
    def emitted_line_number(emitted, statement)
      index = emitted.lines.index { |line| line.include?(statement) }
      index&.+(1)
    end

    def numbered(emitted)
      emitted.lines.map.with_index(1) { |line, number| format('%3d| %s', number, line) }.join
    end

    # All line numbers the VM records for +iseq+ and its children — the lines
    # a debugger can bind a `break file:N` to.
    def iseq_lines(iseq)
      lines = iseq.trace_points.map(&:first)
      iseq.each_child { |child| lines.concat(iseq_lines(child)) }
      lines
    end
  end
end

# frozen_string_literal: true

require 'ast_transform/transformer'
require 'ast_transform/instruction_sequence'

module ASTTransform
  # Assertions for transform authors' own test suites — the enforcement arm
  # of the authoring contract ("textual order is source order"). Never loaded
  # in production; require it from test code:
  #
  #   require "ast_transform/test_helpers"
  #
  #   class MyTransformationTest < Minitest::Test
  #     include ASTTransform::TestHelpers
  #   end
  module TestHelpers
    # Transforms +source+ through the real pipeline (transform + line-aligned
    # emission), re-parses both sides, matches surviving statements by
    # location, and asserts each one's emitted line equals its source line.
    # Statements the transform deletes (e.g. description strings) are exempt;
    # statements the transform rewrites in place keep their anchor and are
    # checked.
    #
    # @param source [String] fixture source
    # @param transformations [Array<ASTTransform::AbstractTransformation>]
    # @param path [String] pseudo-path used for parsing and messages
    # @return [void]
    def assert_line_aligned(source, *transformations, path: 'fixture.rb')
      transformer = Transformer.new(*transformations)
      emitted = transformer.transform_file_source(source, path, path)

      source_lines_by_statement = statement_lines(transformer.build_ast(source, file_path: path))
      emitted_lines_by_statement = statement_lines(transformer.build_ast(emitted, file_path: path))

      misaligned = source_lines_by_statement.filter_map do |render, source_line|
        emitted_line = emitted_lines_by_statement[render]
        next if emitted_line.nil? || emitted_line == source_line

        format('  MISALIGNED %s: source line %d, emitted line %d', render, source_line, emitted_line)
      end

      assert misaligned.empty?, <<~MESSAGE
        expected every surviving statement at its source line in #{path}:
        #{misaligned.join("\n")}

        emitted:
        #{numbered_listing(emitted)}
      MESSAGE
    end

    # Runtime complement of assert_line_aligned: compiles +source+ through
    # the full pipeline under +path+, executes it, and asserts the raw first
    # backtrace frame — no filtering of any kind — is "<path>:<raise_at>".
    #
    # @param source [String] fixture that raises when executed
    # @param path [String] pseudo source path to compile under
    # @param raise_at [Integer] expected source line of the raise
    # @return [void]
    def assert_backtrace_lines(source, path:, raise_at:)
      iseq = InstructionSequence.source_to_transformed_iseq(source, path)

      error = assert_raises(StandardError, "fixture at #{path} should raise when executed") do
        iseq.eval
      end

      location = error.backtrace_locations.first
      assert_equal "#{location.path}:#{raise_at}", "#{location.path}:#{location.lineno}",
        "raw backtrace should cite source line #{raise_at} of #{path}"
    end

    private

    # Flat statement renders and their first line, keyed by unparsed text so
    # source and emitted sides can be matched without location identity.
    # Duplicate renders keep their first occurrence — good enough for
    # fixtures, which authors control.
    def statement_lines(ast, lines = {})
      return lines unless ast.is_a?(::Parser::AST::Node)

      if statement_sequence?(ast)
        ast.children.each do |statement|
          next unless statement.is_a?(::Parser::AST::Node) && statement.loc&.expression

          lines[Unparser.unparse(statement)] ||= statement.loc.line
        end
      end

      ast.children.each { |child| statement_lines(child, lines) }
      lines
    end

    def statement_sequence?(node)
      [:begin, :kwbegin].include?(node.type)
    end

    def numbered_listing(source)
      source.lines.map.with_index(1) { |line, number| format('%3d| %s', number, line) }.join
    end
  end
end

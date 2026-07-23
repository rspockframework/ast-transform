# frozen_string_literal: true
require 'test_helper'
require 'ast_transform/line_aligned_emitter'
require 'ast_transform/transformation_helper'
require 'ast_transform/transformer'

module ASTTransform
  class LineAlignedEmitterTest < Minitest::Test
    extend ASTTransform::Declarative
    include ASTTransform::TransformationHelper

    class UnloweredNode < ASTTransform::Node
      register :ast_transform_emitter_test_custom
    end

    def parse(source)
      ASTTransform::Transformer.new.build_ast(source)
    end

    def emit(ast)
      LineAlignedEmitter.new(ast, 'fixture.rb').emit
    end

    test "emits deferral pairs as a hidden-lvar lambda and its call" do
      given, when_statement, interaction = parse("given_setup\nwhen_body\ninteraction_setup\n").children
      reordered = run_after([given, when_statement, interaction], run: [when_statement], after: interaction)

      emitted = emit(s(:begin, *reordered))

      assert_includes emitted, '__ast_deferred_1__ = ->', emitted
      assert_includes emitted, 'when_body', emitted
      assert_includes emitted, '__ast_deferred_1__.call', emitted
      # Execution order: lambda defined, interaction runs, then the call.
      assert_operator emitted.index('interaction_setup'), :<, emitted.index('__ast_deferred_1__.call'), emitted
    end

    test "deferred body statements stay on their source lines inside the lambda" do
      source = <<~HEREDOC
        given_setup
        when_body_first
        when_body_second
        interaction_setup
      HEREDOC
      given, first, second, interaction = parse(source).children
      reordered = run_after([given, first, second, interaction], run: [first, second], after: interaction)

      emitted = emit(s(:begin, *reordered))

      assert_equal 2, emitted.lines.index { |line| line.include?('when_body_first') } + 1, emitted
      assert_equal 3, emitted.lines.index { |line| line.include?('when_body_second') } + 1, emitted
    end

    test "a placement may be executed from multiple call sites (multiplexing)" do
      statement = parse("shared_body\n")
      deferral = defer(statement)

      emitted = emit(s(:begin, deferral.placement, deferral.execution, deferral.execution))

      assert_equal 2, emitted.scan('__ast_deferred_1__.call').size, emitted
    end

    test "a placement with no execution point raises UnmatchedDeferralError" do
      deferral = defer(parse("orphan_body\n"))

      error = assert_raises(UnmatchedDeferralError) { emit(s(:begin, deferral.placement)) }

      assert_includes error.message, 'never executed'
    end

    test "an execution point before its placement raises UnmatchedDeferralError" do
      deferral = defer(parse("body\n"))

      error = assert_raises(UnmatchedDeferralError) do
        emit(s(:begin, deferral.execution, deferral.placement))
      end

      assert_includes error.message, 'before'
    end

    test "a duplicate placement raises UnmatchedDeferralError" do
      deferral = defer(parse("body\n"))

      error = assert_raises(UnmatchedDeferralError) do
        emit(s(:begin, deferral.placement, deferral.placement, deferral.execution))
      end

      assert_includes error.message, 'duplicate'
    end

    test "distinct deferrals get distinct hidden lvar names" do
      first_deferral = defer(parse("first_body\n"))
      second_deferral = defer(parse("second_body\n"))

      emitted = emit(s(:begin,
        first_deferral.placement, second_deferral.placement,
        first_deferral.execution, second_deferral.execution))

      assert_includes emitted, '__ast_deferred_1__ = ->', emitted
      assert_includes emitted, '__ast_deferred_2__ = ->', emitted
    end

    test "an unlowered custom node type raises UnloweredNodeTypeError" do
      error = assert_raises(UnloweredNodeTypeError) do
        emit(s(:begin, s(:ast_transform_emitter_test_custom)))
      end

      assert_includes error.message, 'ast_transform_emitter_test_custom'
    end

    test "rescue/else/ensure keywords and their statements emit at their source lines" do
      source = <<~HEREDOC
        def risky
          compute
        rescue ArgumentError, TypeError => error
          handle(error)
        else
          celebrate
        ensure
          cleanup
        end
      HEREDOC

      emitted_lines = emit(parse(source)).lines.map(&:strip)

      assert_equal ['def risky', 'compute', 'rescue ArgumentError, TypeError => error', 'handle(error)',
        'else', 'celebrate', 'ensure', 'cleanup', 'end'], emitted_lines
    end

    test "a standalone begin/end block emits its statements at their source lines" do
      source = <<~HEREDOC
        begin
          first_call
          second_call
        end
      HEREDOC

      emitted_lines = emit(parse(source)).lines.map(&:strip)

      assert_equal ['begin', 'first_call', 'second_call', 'end'], emitted_lines
    end

    test "compress_to_single_line declines renders whose single-line join does not parse" do
      emitter = LineAlignedEmitter.new(parse("noop\n"), 'fixture.rb')

      # No current Unparser render joins into invalid syntax (heredocs are
      # normalized to inline strings), so exercise the totality guard
      # directly: layout must fall back, never raise, whatever future
      # Unparser output looks like.
      assert_nil emitter.send(:compress_to_single_line, "value = <<~TXT\n  hi\nTXT")
    end

    test "execution markers compose inside expressions" do
      when_body = parse("raise_helper\n")
      deferral = defer(when_body)
      assert_raises_call = s(:block,
        s(:send, nil, :assert_raises, s(:const, nil, :RuntimeError)),
        s(:args),
        deferral.execution)

      emitted = emit(s(:begin, deferral.placement, assert_raises_call))

      assert_includes emitted, 'assert_raises(RuntimeError)', emitted
      assert_includes emitted, '__ast_deferred_1__.call', emitted
    end
  end
end

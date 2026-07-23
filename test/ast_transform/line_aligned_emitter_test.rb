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

    # Runs emitted code with real method semantics (return target, method
    # scope for locals) — exactly the environment deferred code lives in.
    def run_as_method(emitted)
      harness = Module.new
      harness.module_eval("def self.run_case\n#{emitted}\nend", 'fixture.rb', 0)
      harness.run_case
    end

    test "emits deferral pairs as a hidden-lvar proc and its call" do
      given, when_statement, interaction = parse("given_setup\nwhen_body\ninteraction_setup\n").children
      reordered = run_after([given, when_statement, interaction], run: [when_statement], after: interaction)

      emitted = emit(s(:begin, *reordered))

      assert_includes emitted, '__ast_deferred_1__ = proc', emitted
      assert_includes emitted, 'when_body', emitted
      assert_includes emitted, '__ast_deferred_1__.call', emitted
      # Execution order: proc defined, interaction runs, then the call.
      assert_operator emitted.index('interaction_setup'), :<, emitted.index('__ast_deferred_1__.call'), emitted
    end

    test "deferred body statements stay on their source lines inside the proc" do
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

      assert_includes emitted, '__ast_deferred_1__ = proc', emitted
      assert_includes emitted, '__ast_deferred_2__ = proc', emitted
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

    test "pre-declares locals the deferred statements assign at method scope" do
      first, second, third = parse("given_setup\nresult = compute\ninteraction_setup\n").children
      reordered = run_after([first, second, third], run: [second], after: third)

      emitted = emit(s(:begin, *reordered))

      assert_includes emitted, 'result = result; __ast_deferred_1__ = proc', emitted
    end

    test "pre-declarations skip block-local assignments but cover the block call's arguments" do
      source = <<~HEREDOC
        outer = items.map { |item| inner = item }
        buffer.take(width = limit) { |line| sink(line) }
      HEREDOC
      deferral = defer(*parse(source).children)

      emitted = emit(s(:begin, deferral.placement, deferral.execution))

      assert_includes emitted, 'outer = outer', emitted
      # width is assigned in the block call's ARGUMENTS, which evaluate at
      # method scope; inner is first assigned inside the block, so it is
      # block-local in the original source too.
      assert_includes emitted, 'width = width', emitted
      refute_includes emitted, 'inner = inner', emitted
    end

    test "pre-declarations skip assignments inside nested defs" do
      deferral = defer(parse("def helper = (scoped = 1)\n"))

      emitted = emit(s(:begin, deferral.placement, deferral.execution))

      refute_includes emitted, 'scoped = scoped', emitted
    end

    test "a deferred assignment runs late but propagates to the enclosing method scope" do
      source = <<~HEREDOC
        log = []
        result = log.size
        log << :setup
        [log, result]
      HEREDOC
      first, second, third, fourth = parse(source).children
      reordered = run_after([first, second, third, fourth], run: [second], after: third)

      # Deferred `result = log.size` runs after `log << :setup`, so result is
      # 1 (textual order would give 0) — proving both the reordering and that
      # the assignment escaped the proc into the method scope.
      assert_equal [[:setup], 1], run_as_method(emit(s(:begin, *reordered)))
    end

    test "a pre-declaration does not clobber an already-assigned local" do
      source = <<~HEREDOC
        value = :given
        value = :reassigned
        snapshot = value
        [snapshot, value]
      HEREDOC
      first, second, third, fourth = parse(source).children
      reordered = run_after([first, second, third, fourth], run: [second], after: third)

      # snapshot reads value between the proc's definition and its call: the
      # pre-declaration must preserve :given, and the deferred reassignment
      # must land afterwards.
      assert_equal [:given, :reassigned], run_as_method(emit(s(:begin, *reordered)))
    end

    test "a deferred return exits the enclosing method (non-lambda proc semantics)" do
      source = <<~HEREDOC
        log = []
        return [:early, log] unless log.empty?
        log << :setup
        :late
      HEREDOC
      first, second, third, fourth = parse(source).children
      reordered = run_after([first, second, third, fourth], run: [second], after: third)

      # The deferred return fires from inside the proc but returns from the
      # method — and only after the setup it was deferred past has run.
      assert_equal [:early, [:setup]], run_as_method(emit(s(:begin, *reordered)))
    end

    test "a deferred break severed from its loop keeps Ruby's native LocalJumpError" do
      deferral = defer(parse("break\n"))

      emitted = emit(s(:begin, deferral.placement, deferral.execution))

      assert_raises(LocalJumpError) { run_as_method(emitted) }
    end

    test "statements inside an it-block container stay on their source lines" do
      source = <<~HEREDOC
        items.each do
          first_call(it)

          second_call(it)
        end
      HEREDOC

      emitted_lines = emit(parse(source)).lines.map(&:strip)

      assert_equal 2, emitted_lines.index { |line| line.include?('first_call') } + 1, emitted_lines.join
      assert_equal 4, emitted_lines.index { |line| line.include?('second_call') } + 1, emitted_lines.join
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

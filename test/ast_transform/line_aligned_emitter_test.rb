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
      LineAlignedEmitter.new.emit(ast, 'fixture.rb')
    end

    # Runs emitted code with real method semantics (return target, method
    # scope for locals) — exactly the environment thunked code lives in.
    def run_as_method(emitted)
      harness = Module.new
      harness.module_eval("def self.run_case\n#{emitted}\nend", 'fixture.rb', 0)
      harness.run_case
    end

    test "lowers a thunk to a hidden-lvar proc at the body's source lines and its call" do
      given, when_statement, interaction = parse("given_setup\nwhen_body\ninteraction_setup\n").children
      reordered = run_after([given, when_statement, interaction], run: [when_statement], after: interaction)

      emitted = emit(s(:begin, *reordered))

      assert_includes emitted, '__ast_thunk_1__ = proc', emitted
      assert_includes emitted, 'when_body', emitted
      assert_includes emitted, '__ast_thunk_1__.call', emitted
      # Execution order: proc defined, interaction runs, then the call.
      assert_operator emitted.index('interaction_setup'), :<, emitted.index('__ast_thunk_1__.call'), emitted
    end

    test "thunk body statements stay on their source lines inside the proc" do
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

    test "reusing one thunk node executes its body from multiple call sites (multiplexing)" do
      shared = thunk(parse("shared_body\n"))

      emitted = emit(s(:begin, shared, shared))

      assert_equal 1, emitted.scan('__ast_thunk_1__ = proc').size, emitted
      assert_equal 2, emitted.scan('__ast_thunk_1__.call').size, emitted
    end

    test "a thunk whose body lines fall after its execution point raises ThunkLowering::PlacementError" do
      first, second, third = parse("first\nsecond\nthird\n").children
      # third's text (line 3) cannot execute after first (line 1) yet before
      # second (line 2): the proc's text IS its assignment.
      reordered = run_after([first, second, third], run: [third], after: first)

      error = assert_raises(ThunkLowering::PlacementError) { emit(s(:begin, *reordered)) }

      assert_includes error.message, 'fall after its execution point'
    end

    test "occurrences of one thunk with diverging bodies raise ThunkLowering::PlacementError" do
      original = thunk(parse("foo\n"))
      diverged = original.updated(nil, [original.id, parse("bar\n")])

      error = assert_raises(ThunkLowering::PlacementError) { emit(s(:begin, original, diverged)) }

      assert_includes error.message, 'diverging'
    end

    test "a loc-less thunk body packs immediately before its call" do
      synthetic = thunk(s(:send, nil, :synthetic_body))

      emitted = emit(s(:begin, parse("real_statement\n"), synthetic))

      assert_includes emitted, 'real_statement; __ast_thunk_1__ = proc', emitted
      assert_operator emitted.index('synthetic_body'), :<, emitted.index('__ast_thunk_1__.call'), emitted
    end

    test "distinct thunks get distinct hidden lvar names" do
      first_thunk = thunk(parse("first_body\n"))
      second_thunk = thunk(parse("second_body\n"))

      emitted = emit(s(:begin, first_thunk, second_thunk))

      assert_includes emitted, '__ast_thunk_1__ = proc', emitted
      assert_includes emitted, '__ast_thunk_2__ = proc', emitted
    end

    test "an unlowered custom node type raises LineAlignedEmitter::UnloweredNodeTypeError" do
      error = assert_raises(LineAlignedEmitter::UnloweredNodeTypeError) do
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

    # A fully synthetic ensure (e.g. a transform wrapping a body in teardown, like RSpock's Cleanup) has no keyword
    # line to target: the keyword must open a fresh line, never `;`-pack after the preceding statement.
    test "a loc-less ensure keyword goes on a fresh line, never packed" do
      synthetic_def = s(:def, :run, s(:args),
        s(:ensure, s(:send, nil, :work), s(:send, nil, :cleanup)))

      emitted = emit(synthetic_def)

      # Everything is loc-less, so it packs — except the keyword, which opens a fresh line.
      assert_equal <<~RUBY, emitted
        def run; work
        ensure; cleanup; end
      RUBY
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

    test "pre-declares locals the thunk body assigns at method scope" do
      first, second, third = parse("given_setup\nresult = compute\ninteraction_setup\n").children
      reordered = run_after([first, second, third], run: [second], after: third)

      emitted = emit(s(:begin, *reordered))

      assert_includes emitted, 'result = result; __ast_thunk_1__ = proc', emitted
    end

    test "pre-declarations skip block-local assignments but cover the block call's arguments" do
      source = <<~HEREDOC
        outer = items.map { |item| inner = item }
        buffer.take(width = limit) { |line| sink(line) }
      HEREDOC

      emitted = emit(s(:begin, thunk(*parse(source).children)))

      assert_includes emitted, 'outer = outer', emitted
      # width is assigned in the block call's ARGUMENTS, which evaluate at
      # method scope; inner is first assigned inside the block, so it is
      # block-local in the original source too.
      assert_includes emitted, 'width = width', emitted
      refute_includes emitted, 'inner = inner', emitted
    end

    test "pre-declarations skip assignments inside nested defs" do
      emitted = emit(s(:begin, thunk(parse("def helper = (scoped = 1)\n"))))

      refute_includes emitted, 'scoped = scoped', emitted
    end

    test "a thunked assignment runs late but propagates to the enclosing method scope" do
      source = <<~HEREDOC
        log = []
        result = log.size
        log << :setup
        [log, result]
      HEREDOC
      first, second, third, fourth = parse(source).children
      reordered = run_after([first, second, third, fourth], run: [second], after: third)

      # Thunked `result = log.size` runs after `log << :setup`, so result is
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
      # pre-declaration must preserve :given, and the thunked reassignment
      # must land afterwards.
      assert_equal [:given, :reassigned], run_as_method(emit(s(:begin, *reordered)))
    end

    test "a thunked return exits the enclosing method (non-lambda proc semantics)" do
      source = <<~HEREDOC
        log = []
        return [:early, log] unless log.empty?
        log << :setup
        :late
      HEREDOC
      first, second, third, fourth = parse(source).children
      reordered = run_after([first, second, third, fourth], run: [second], after: third)

      # The thunked return fires from inside the proc but returns from the
      # method — and only after the setup it was thunked past has run.
      assert_equal [:early, [:setup]], run_as_method(emit(s(:begin, *reordered)))
    end

    test "a thunked break severed from its loop keeps Ruby's native LocalJumpError" do
      emitted = emit(s(:begin, thunk(parse("break\n"))))

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

    test "a thunk composes inside expressions; its placement hoists to the enclosing sequence" do
      when_body = parse("raise_helper\n")
      assert_raises_call = s(:block,
        s(:send, nil, :assert_raises, s(:const, nil, :RuntimeError)),
        s(:args),
        thunk(when_body))

      emitted = emit(s(:begin, assert_raises_call))

      assert_includes emitted, '__ast_thunk_1__ = proc', emitted
      assert_includes emitted, 'assert_raises(RuntimeError)', emitted
      assert_includes emitted, '__ast_thunk_1__.call', emitted
      # The proc's definition precedes the assert_raises call that runs it.
      assert_operator emitted.index('__ast_thunk_1__ = proc'), :<, emitted.index('assert_raises'), emitted
    end

    test "a thunk inside a def stays inside the def (scope boundary)" do
      def_node = parse("def run\n  helper\nend\n")
      name, args, body = def_node.children
      thunked_def = def_node.updated(nil, [name, args, thunk(body)])

      emitted = emit(thunked_def)

      # The proc and its call both sit between the def opener and its end;
      # the body statement keeps its source line.
      assert_operator emitted.index('def run'), :<, emitted.index('__ast_thunk_1__ = proc'), emitted
      assert_operator emitted.index('__ast_thunk_1__.call'), :<, emitted.rindex('end'), emitted
      assert_equal 2, emitted.lines.index { |line| line.include?('helper') } + 1, emitted
    end
  end
end

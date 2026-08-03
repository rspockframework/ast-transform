# frozen_string_literal: true

require 'ast_transform/node'
require 'ast_transform/layout'
require 'ast_transform/statement_renderer'
require 'ast_transform/thunk_lowering'

module ASTTransform
  # Emits a transformed AST as text in which every loc-carrying statement occupies its original source line, so that
  # backtraces, breakpoints and debugger display are correct by construction — CRuby derives line numbers from
  # physical text position, so placement is our line table.
  #
  # Placement policy over statement sequences:
  #
  # 1. Statement has loc: target its source line — the Layout pads to reach it, or packs (`; `) when the cursor has
  #    already passed it. A user statement packing means the transform moved it — the alignment auditor's concern,
  #    not a runtime failure.
  # 2. No loc: pack onto the current line — synthetic code has no source-line truth to preserve.
  #
  # The emitter owns the Ruby knowledge: walking statement structure, deciding which line each node targets, and
  # that keywords can never be `;`-packed. The pad-or-pack mechanics live in Layout; statement-to-text rendering
  # (and its isolation workarounds) in StatementRenderer — both created per emission, so the emitter itself is
  # stateless and an instance is a reusable collaborator.
  #
  # Thunk nodes are lowered (ThunkLowering) before layout; the emitter's postcondition is that no custom node type
  # (ast_* markers or types registered on ASTTransform::Node) crosses the unparse boundary — they are IR between
  # stages that understand them.
  class LineAlignedEmitter
    # Raised as the emitter's postcondition when a custom node type (ast_* markers or types registered on
    # ASTTransform::Node) reaches the unparse boundary instead of being lowered by the stage that understands it.
    class UnloweredNodeTypeError < StandardError; end

    # Containers the emitter recurses into so nested statements align; every other node renders as an Unparser blob
    # at its head line.
    RECURSIVE_CONTAINER_TYPES = [:class, :module, :sclass, :def, :defs, :block, :numblock, :itblock, :kwbegin].freeze
    BODY_INDEXES = {
      class: 2, module: 1, sclass: 1, def: 2, defs: 3, block: 2, numblock: 2, itblock: 2
    }.freeze
    # Assignments whose value is a block (e.g. the lowered thunk proc) recurse into the block so its body statements
    # align.
    ASSIGNMENT_TYPES = [:lvasgn, :ivasgn, :gvasgn, :casgn].freeze
    BLOCK_VALUE_TYPES = [:block, :numblock, :itblock].freeze

    # @param thunk_lowering [ThunkLowering] the lowering run ahead of emission.
    def initialize(thunk_lowering: ThunkLowering.new)
      @thunk_lowering = thunk_lowering
    end

    # @param ast [Parser::AST::Node] transformed AST
    # @param source_path [String] original file path (for error messages)
    # @return [String] transformed source, line-aligned
    # @raise [ThunkLowering::PlacementError] if a thunk cannot be textually placed
    # @raise [UnloweredNodeTypeError] if a custom node type survived to emission
    def emit(ast, source_path)
      lowered = @thunk_lowering.lower(ast)
      assert_no_custom_types(lowered, source_path)

      layout = Layout.new
      renderer = StatementRenderer.for_tree(lowered)
      emit_statements(statements_of(lowered), layout, renderer)
      layout.to_source
    end

    private

    def emit_statements(statements, layout, renderer)
      statements.each { |statement| emit_statement(statement, layout, renderer) }
    end

    def emit_statement(node, layout, renderer)
      if recursive_container?(node)
        emit_container(node, layout, renderer)
      else
        render = renderer.aligned_render(node)
        # A render in heredoc form seals its line: nothing may pack after the terminator (issue #16).
        layout.place(node.loc&.line, render, column: node.loc&.column, seal: renderer.line_terminal?(render))
      end
    end

    # Emits a container body that may be a bare :ensure/:rescue node (their begin/end context comes from the
    # surrounding def/block/kwbegin, so the keywords must be emitted inline, aligned like statements).
    def emit_body(body, layout, renderer)
      case body&.type
      when :ensure then emit_ensure(body, layout, renderer)
      when :rescue then emit_rescue(body, layout, renderer)
      else emit_statements(statements_of(body), layout, renderer)
      end
    end

    def emit_ensure(node, layout, renderer)
      *body, ensurer = node.children
      body.each { |statement| emit_body(statement, layout, renderer) }
      place_keyword(layout, keyword_line(node), 'ensure', column: keyword_column(node))
      emit_statements(statements_of(ensurer), layout, renderer)
    end

    def emit_rescue(node, layout, renderer)
      body, *resbodies, else_body = node.children
      emit_body(body, layout, renderer)
      resbodies.each { |resbody| emit_resbody(resbody, layout, renderer) }
      return if else_body.nil?

      else_range = node.loc.else if node.loc.respond_to?(:else)
      place_keyword(layout, else_range&.line, 'else', column: else_range&.column)
      emit_statements(statements_of(else_body), layout, renderer)
    end

    def emit_resbody(node, layout, renderer)
      exceptions, capture, body = node.children
      header = ['rescue']
      header << " #{renderer.unparse(exceptions).delete_prefix('[').delete_suffix(']')}" if exceptions
      header << " => #{capture.children[0]}" if capture
      place_keyword(layout, node.loc&.line, header.join, column: node.loc&.column)
      emit_statements(statements_of(body), layout, renderer)
    end

    # Keywords (rescue/ensure/else) cannot be `;`-packed after a statement; when their line is taken they go on a
    # fresh line instead.
    def place_keyword(layout, target_line, keyword, column: nil)
      if target_line && target_line > layout.cursor
        layout.place(target_line, keyword, column: column)
      else
        layout.place_on_fresh_line(keyword)
      end
    end

    def keyword_line(node)
      loc = node.loc
      loc.keyword.line if loc.respond_to?(:keyword) && loc.keyword
    end

    def keyword_column(node)
      loc = node.loc
      loc.keyword.column if loc.respond_to?(:keyword) && loc.keyword
    end

    def recursive_container?(node)
      RECURSIVE_CONTAINER_TYPES.include?(node.type) || block_assignment?(node)
    end

    def block_assignment?(node)
      ASSIGNMENT_TYPES.include?(node.type) && node.children.last.is_a?(::Parser::AST::Node) &&
        BLOCK_VALUE_TYPES.include?(node.children.last.type)
    end

    # Renders a container's opener and closer from the node with its body emptied, then recurses into the body so
    # nested statements align.
    def emit_container(node, layout, renderer)
      opener, closer = container_delimiters(node, renderer)
      # An opener can carry a heredoc too (e.g. a block call with a heredoc argument) — seal it like a statement.
      layout.place(node.loc&.line, opener, column: node.loc&.column, seal: renderer.line_terminal?(opener))
      emit_body(container_body(node), layout, renderer)
      layout.place(closer_line(node), closer, column: closer_column(node))
    end

    def container_delimiters(node, renderer)
      rendered = renderer.unparse(empty_container(node)).split("\n").reject(&:empty?)
      opener = rendered[0..-2].join("\n")
      closer = rendered.last

      # Unparser renders empty blocks with braces, but brace blocks cannot hold rescue/ensure bodies; do/end always
      # can.
      if opener.end_with?(' {') && closer == '}'
        [opener.sub(/ \{\z/, ' do'), 'end']
      else
        [opener, closer]
      end
    end

    def empty_container(node)
      case node.type
      when :kwbegin
        node.updated(nil, [])
      when *ASSIGNMENT_TYPES
        block_node = node.children.last
        emptied_block = block_node.updated(nil, [*block_node.children[0..-2], nil])
        node.updated(nil, [*node.children[0..-2], emptied_block])
      else
        children = node.children.dup
        children[BODY_INDEXES.fetch(node.type)] = nil
        node.updated(nil, children)
      end
    end

    def container_body(node)
      case node.type
      when :kwbegin then node.children.size == 1 ? node.children.first : node.updated(:begin, node.children)
      when *ASSIGNMENT_TYPES then node.children.last.children[2]
      else node.children[BODY_INDEXES.fetch(node.type)]
      end
    end

    # The line the container's `end`/`}` occupies in the source, when known.
    def closer_line(node)
      loc = node.loc
      loc.end.line if loc.respond_to?(:end) && loc.end
    end

    def closer_column(node)
      loc = node.loc
      loc.end.column if loc.respond_to?(:end) && loc.end
    end

    # Loc-less :begin nodes in statement position (e.g. a lowered thunk in a single-statement container body, carried
    # with its placement) are grouping, not structure: flatten them so each inner statement is laid out independently.
    def statements_of(body)
      return [] if body.nil?
      return [body] unless body.type == :begin

      body.children.flat_map do |child|
        child.is_a?(::Parser::AST::Node) && child.type == :begin && child.loc.nil? ? statements_of(child) : [child]
      end
    end

    def assert_no_custom_types(node, source_path)
      return unless node.is_a?(::Parser::AST::Node)

      if node.type.start_with?('ast_') || Node.registry.key?(node.type)
        raise UnloweredNodeTypeError,
          "custom node type :#{node.type} reached emission in #{source_path}; custom types are " \
            "IR between transformation stages and must be lowered by the stage that understands them"
      end

      node.children.each { |child| assert_no_custom_types(child, source_path) }
    end
  end
end

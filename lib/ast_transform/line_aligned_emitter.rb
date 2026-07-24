# frozen_string_literal: true

require 'unparser'
require 'ast_transform/node'
require 'ast_transform/errors'
require 'ast_transform/thunk_lowering'

module ASTTransform
  # Emits a transformed AST as text in which every loc-carrying statement occupies its original source line, so that
  # backtraces, breakpoints and debugger display are correct by construction — CRuby derives line numbers from
  # physical text position, so placement is our line table.
  #
  # Cursor algorithm over statement sequences:
  #
  # 1. Statement has loc and target_line > cursor: pad with newlines, emit at the target line, indented to the
  #    statement's source column.
  # 2. Statement has loc and target_line <= cursor: pack (`; `) onto the current line. A user statement landing here
  #    means the transform moved it — the alignment auditor's concern, not a runtime failure.
  # 3. No loc: pack onto the current line — synthetic code has no source-line truth to preserve.
  #
  # Multi-line renders advance the cursor by their height; displaced statements pack and emission re-anchors at the
  # next statement that fits. Total: never raises on layout.
  #
  # Thunk nodes are lowered (ThunkLowering) before layout; the emitter's postcondition is that no custom node type
  # (ast_* markers or types registered on ASTTransform::Node) crosses the unparse boundary — they are IR between
  # stages that understand them.
  class LineAlignedEmitter
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

    # @param ast [Parser::AST::Node] transformed AST
    # @param source_path [String] original file path (for error messages)
    def initialize(ast, source_path)
      @ast = ast
      @source_path = source_path
      @local_variables = Set.new
    end

    # @return [String] transformed source, line-aligned
    # @raise [ThunkPlacementError] if a thunk cannot be textually placed
    # @raise [UnloweredNodeTypeError] if a custom node type survived to emission
    def emit
      lowered = ThunkLowering.new.run(@ast)
      assert_no_custom_types(lowered)

      @local_variables = collect_local_variables(lowered)
      @lines = []
      emit_statements(statements_of(lowered))
      "#{@lines.join("\n")}\n"
    end

    private

    def emit_statements(statements)
      statements.each { |statement| emit_statement(statement) }
    end

    def emit_statement(node)
      if recursive_container?(node)
        emit_container(node)
      else
        place(node.loc&.line, aligned_render(node), column: node.loc&.column)
      end
    end

    # Unparser normalizes some single-line constructs into multi-line form (e.g. modifier-if into if/end), which
    # would push following statements off their lines. When the render is taller than the statement's source,
    # compress it back to one line — verified by re-parse so a statement that cannot be safely single-lined
    # (e.g. containing a heredoc) falls back to its multi-line render and re-anchors after itself.
    def aligned_render(node)
      render = unparse(node)
      loc = node.loc
      return render unless loc.respond_to?(:last_line) && loc.line

      source_height = loc.last_line - loc.line + 1
      return render if render.count("\n") < source_height

      compress_to_single_line(render) || render
    end

    def compress_to_single_line(render)
      candidate = render.split("\n").map(&:strip).join('; ')
      # Both sides parsed without scope context, so lvar/send ambiguity cancels out; equality means the newline join
      # preserved structure.
      Unparser.parse(candidate) == Unparser.parse(render) ? candidate : nil
    rescue Parser::SyntaxError
      nil
    end

    # Statements are unparsed in isolation, losing the surrounding scope's local-variable context; without it,
    # Unparser re-parses identifiers as method calls and its dstr round-trip verification fails. Feed it every local
    # assigned or bound anywhere in the tree — an over-approximation that is safe because it only informs Unparser's
    # re-parse verification.
    def unparse(node)
      Unparser.unparse(node, static_local_variables: @local_variables)
    end

    LOCAL_BINDING_TYPES = [:lvasgn, :arg, :optarg, :restarg, :kwarg, :kwoptarg, :blockarg, :shadowarg].freeze

    def collect_local_variables(node, names = Set.new)
      return names unless node.is_a?(::Parser::AST::Node)

      names << node.children[0] if LOCAL_BINDING_TYPES.include?(node.type) && node.children[0]
      node.children.each { |child| collect_local_variables(child, names) }
      names
    end

    # Emits a container body that may be a bare :ensure/:rescue node (their begin/end context comes from the
    # surrounding def/block/kwbegin, so the keywords must be emitted inline, aligned like statements).
    def emit_body(body)
      case body&.type
      when :ensure then emit_ensure(body)
      when :rescue then emit_rescue(body)
      else emit_statements(statements_of(body))
      end
    end

    def emit_ensure(node)
      *body, ensurer = node.children
      body.each { |statement| emit_body(statement) }
      place_keyword(keyword_line(node), 'ensure', column: keyword_column(node))
      emit_statements(statements_of(ensurer))
    end

    def emit_rescue(node)
      body, *resbodies, else_body = node.children
      emit_body(body)
      resbodies.each { |resbody| emit_resbody(resbody) }
      return if else_body.nil?

      else_range = node.loc.else if node.loc.respond_to?(:else)
      place_keyword(else_range&.line, 'else', column: else_range&.column)
      emit_statements(statements_of(else_body))
    end

    def emit_resbody(node)
      exceptions, capture, body = node.children
      header = ['rescue']
      header << " #{Unparser.unparse(exceptions).delete_prefix('[').delete_suffix(']')}" if exceptions
      header << " => #{capture.children[0]}" if capture
      place_keyword(node.loc&.line, header.join, column: node.loc&.column)
      emit_statements(statements_of(body))
    end

    # Keywords (rescue/ensure/else) cannot be `;`-packed after a statement; when their line is taken they go on a
    # fresh line instead.
    def place_keyword(target_line, keyword, column: nil)
      if target_line && target_line > @lines.size
        place(target_line, keyword, column: column)
      else
        @lines << keyword
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
    def emit_container(node)
      opener, closer = container_delimiters(node)
      place(node.loc&.line, opener, column: node.loc&.column)
      emit_body(container_body(node))
      place(closer_line(node), closer, column: closer_column(node))
    end

    def container_delimiters(node)
      rendered = unparse(empty_container(node)).split("\n").reject(&:empty?)
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

    # Places +render+ at +target_line+ when the cursor hasn't passed it; otherwise packs onto the current line.
    # Multi-line renders advance the cursor by their height. When opening a fresh line, the render is indented to the
    # statement's source +column+ — cosmetic only (leading whitespace is never significant in emitted code; heredocs
    # are normalized to inline strings), but it keeps the artifact and test expectations visually close to the
    # source. Packed statements ignore the column, as do an Unparser render's continuation lines (they keep
    # Unparser's own relative indentation).
    def place(target_line, render, column: nil)
      first, *rest = render.split("\n")

      if target_line && target_line > @lines.size
        @lines << '' while @lines.size < target_line
        @lines[-1] = indented(first, column)
      else
        pack(first)
      end

      @lines.concat(rest)
    end

    def indented(text, column)
      column && column.positive? ? "#{' ' * column}#{text}" : text
    end

    # The last line is never blank here: padding blanks are only created inside +place+, which immediately overwrites
    # the padded line.
    def pack(text)
      if @lines.empty?
        @lines << text
      else
        @lines[-1] = "#{@lines.last}; #{text}"
      end
    end

    def assert_no_custom_types(node)
      return unless node.is_a?(::Parser::AST::Node)

      if node.type.start_with?('ast_') || Node.registry.key?(node.type)
        raise UnloweredNodeTypeError,
          "custom node type :#{node.type} reached emission in #{@source_path}; custom types are " \
            "IR between transformation stages and must be lowered by the stage that understands them"
      end

      node.children.each { |child| assert_no_custom_types(child) }
    end
  end
end

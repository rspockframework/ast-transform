# frozen_string_literal: true
require 'ast_transform/node'
require 'ast_transform/thunk'
require 'ast_transform/errors'
require 'ast_transform/transformation_helper'

module ASTTransform
  # Lowers Thunk nodes into plain Ruby ahead of emission. Each unique thunk
  # (grouped by token identity) becomes a hidden proc; each occurrence
  # becomes the proc's call:
  #
  #   thunk placed at the execution point
  #     => x = x; __ast_thunk_<n>__ = proc { body }   (at the body's source lines)
  #        ...
  #        __ast_thunk_<n>__.call                     (at the occurrence)
  #
  # Placement is inferred, not authored: the proc's text is inserted into
  # the statement sequence enclosing the occurrence, positioned among its
  # siblings by the body's first source line — the lines the author removed
  # the statements from. A loc-less body has no textual home and packs
  # immediately before its call. Placements never escape a scope boundary
  # (def/class/module bodies absorb their own), because the hidden lvar must
  # share the call's method activation; they DO escape block literals, which
  # close over the defining scope.
  #
  # The closure is a non-lambda proc on purpose: `return` inside a proc
  # returns from the method where the proc was defined, and placement and
  # execution always share one method activation, so a thunked `return`
  # keeps its original meaning. Jump keywords whose owner lies outside the
  # body keep Ruby's native behavior (`break`/`retry` fail loudly,
  # `next`/`redo` silently alter flow) — what a transform chooses to thunk
  # is the transform author's call.
  #
  # The `x = x` pre-declarations cover every local the body assigns at
  # method scope. A local first assigned inside a block literal is
  # block-local, so without a textual method-scope assignment before the
  # proc, thunked assignments would be invisible to the statements that
  # read them after the execution point. Self-assignment registers the name
  # (nil until the thunk runs — exactly what an unexecuted assignment
  # yields) without clobbering an already-assigned value.
  class ThunkLowering
    include TransformationHelper

    # A pending proc definition: +line+ is the body's first source line
    # (nil for fully synthetic bodies), +statements+ the pre-declarations
    # plus the proc assignment.
    Placement = Struct.new(:line, :statements)

    SEQUENCE_TYPES = [:begin, :kwbegin].freeze
    # Scope-opening containers: the hidden lvar cannot be referenced across
    # these boundaries, so placements arising inside must land inside.
    SCOPE_BODY_INDEXES = { def: 2, defs: 3, class: 2, module: 1, sclass: 1 }.freeze

    def initialize
      @names_by_token = {}.compare_by_identity
      @bodies_by_token = {}.compare_by_identity
    end

    # @param node [Parser::AST::Node] tree possibly containing Thunk nodes
    # @return [Parser::AST::Node] tree with thunks lowered to plain Ruby
    # @raise [ThunkPlacementError] when a thunk body's source lines fall
    #   after its execution point, or occurrences of one thunk diverge
    def run(node)
      lower_body(node)
    end

    private

    # Lowers a node standing in statement-body position (a container's body
    # or the root), absorbing any placements that arise within it.
    def lower_body(node)
      return node unless node.is_a?(::Parser::AST::Node)
      return lower_sequence(node) if SEQUENCE_TYPES.include?(node.type)

      lowered, placements = lower_expression(node)
      return lowered if placements.empty?

      # A loc-less :begin in statement position; the emitter flattens it
      # into the surrounding statement stream.
      s(:begin, *placements.flat_map(&:statements), lowered)
    end

    # Lowers a statement sequence, inserting each placement among the
    # statements by the body's source line.
    def lower_sequence(node)
      statements = []

      node.children.each_with_index do |child, index|
        lowered, placements = lower_expression(child)
        placements.each do |placement|
          check_placement_precedes_execution!(placement, child, node.children[(index + 1)..])
          statements.insert(insertion_index(statements, placement), *placement.statements)
        end
        statements << lowered
      end

      node.updated(nil, statements)
    end

    # Lowers a node in expression position. Returns the lowered node and the
    # placements that must be inserted into the enclosing statement
    # sequence.
    #
    # @return [Array(Parser::AST::Node, Array<Placement>)]
    def lower_expression(node)
      return [node, []] unless node.is_a?(::Parser::AST::Node)

      case node.type
      when :ast_thunk
        lower_thunk(node)
      when *SEQUENCE_TYPES
        [lower_sequence(node), []]
      when :ensure, :rescue
        [node.updated(nil, node.children.map { |child| lower_body(child) }), []]
      when :resbody
        exceptions, capture, body = node.children
        [node.updated(nil, [exceptions, capture, lower_body(body)]), []]
      else
        lower_generic(node)
      end
    end

    def lower_generic(node)
      scope_body_index = SCOPE_BODY_INDEXES[node.type]
      pending = []

      children = node.children.each_with_index.map do |child, index|
        if index == scope_body_index
          lower_body(child)
        else
          lowered, placements = lower_expression(child)
          pending.concat(placements)
          lowered
        end
      end

      [node.updated(nil, children), pending]
    end

    # An occurrence of a thunk: the first occurrence of its token yields the
    # placement; every occurrence yields the call.
    def lower_thunk(node)
      token = node.token

      if @names_by_token.key?(token)
        unless @bodies_by_token[token] == node.body
          raise ThunkPlacementError,
            "occurrences of one thunk carry diverging bodies; reuse the same thunk node to multiplex"
        end
        return [call_node(token), []]
      end

      name = :"__ast_thunk_#{@names_by_token.size + 1}__"
      @names_by_token[token] = name
      @bodies_by_token[token] = node.body

      lowered_body = lower_sequence(s(:begin, *node.body))
      placement = Placement.new(body_first_line(node.body), placement_statements(name, lowered_body))
      [call_node(token), [placement]]
    end

    def call_node(token)
      s(:send, s(:lvar, @names_by_token.fetch(token)), :call)
    end

    def placement_statements(name, lowered_body)
      assignment = s(:lvasgn, name, s(:block, s(:send, nil, :proc), s(:args), lowered_body))
      hidden_names = @names_by_token.values
      pre_declared = method_scope_assignments(lowered_body).reject { |local| hidden_names.include?(local) }
      pre_declared.map { |local| s(:lvasgn, local, s(:lvar, local)) } << assignment
    end

    def body_first_line(body)
      body.filter_map { |statement| statement.loc&.line }.min
    end

    # The proc's text must precede its call: a placement whose body lines
    # fall at or after the executing statement (or any statement after it)
    # cannot be laid out — the assignment would complete after the call.
    def check_placement_precedes_execution!(placement, executing_statement, following_statements)
      return if placement.line.nil?

      conflicting = [executing_statement, *following_statements].find do |statement|
        line = statement.is_a?(::Parser::AST::Node) ? statement.loc&.line : nil
        line && line < placement.line
      end
      return if conflicting.nil?

      raise ThunkPlacementError,
        "thunk body's source lines (from line #{placement.line}) fall after its execution point " \
          "(statement at line #{conflicting.loc.line}); a thunk can only delay execution, never text"
    end

    def insertion_index(statements, placement)
      return statements.size if placement.line.nil?

      statements.index { |statement| statement.loc&.line && statement.loc.line > placement.line } || statements.size
    end

    # Node types opening a new local-variable scope: assignments inside them
    # were invisible to the method scope in the original source too, so they
    # get no pre-declaration.
    NEW_SCOPE_TYPES = [:def, :defs, :class, :module, :sclass].freeze
    # Block literals: locals first assigned inside them are block-local (the
    # same lexical rule the pre-declarations exist to work around), but their
    # callee/arguments evaluate at method scope and are still descended.
    BLOCK_TYPES = [:block, :numblock, :itblock].freeze

    # Locals the thunk body assigns at method scope, in first-assignment
    # order (covers masgn/op_asgn targets — they all carry :lvasgn nodes).
    def method_scope_assignments(node, names = [])
      return names unless node.is_a?(::Parser::AST::Node)
      return names if NEW_SCOPE_TYPES.include?(node.type)

      names << node.children[0] if node.type == :lvasgn && !names.include?(node.children[0])

      children = BLOCK_TYPES.include?(node.type) ? [node.children[0]] : node.children
      children.each { |child| method_scope_assignments(child, names) }
      names
    end
  end
end

# frozen_string_literal: true

require 'parser'
require 'ast_transform/node'
require 'ast_transform/thunk'

module ASTTransform
  # The transform-authoring layer. Three shapes:
  #
  # - Constructors (+s+, +s_at+): type + children in, fresh node out.
  # - The sequence combinator (+run_after+): sequence in, sequence out — the paved road for execution reordering.
  # - The low-level reordering primitive (+thunk+): statements in, Thunk node out — for execution points inside
  #   expressions.
  #
  # The contract these helpers serve: textual order is source order. The emitter places every loc-carrying statement
  # at its source line; when execution order must differ from textual order, authors express it as a thunk instead of
  # moving text.
  module TransformationHelper
    # Raised by authoring helpers (e.g. +s_at+) when a node that must carry a source location does not have one.
    class MissingLocationError < StandardError; end

    class << self
      def included(base)
        base.extend(Methods)
        base.include(Methods)
      end
    end

    module Methods
      # Builds a loc-less node. The emitter packs loc-less nodes onto the current output line — the correct default
      # for synthetic code, which has no source-line truth to preserve.
      #
      # @param type [Symbol] node type
      # @param children [Array] child nodes / literals
      # @param properties [Hash] node properties (e.g. location:)
      # @return [ASTTransform::Node] node routed to its registered class
      def s(type, *children, **properties)
        Node.build(type, children, properties)
      end

      # Builds a fresh node anchored to another node's source location. Use when composing a replacement tree whose
      # root isn't derived from the node it replaces (otherwise prefer +anchor.updated(...)+). The attached map is a
      # clean expression-only Source::Map over +anchor.loc.expression+ — no stale typed sub-ranges (selector etc.).
      # Anchor inheritance is shallow; children keep or lack their own locs.
      #
      # @param anchor [Parser::AST::Node] node whose line this code replaces
      # @param type [Symbol] node type
      # @param children [Array] child nodes / literals
      # @return [ASTTransform::Node] node carrying anchor's expression range
      # @raise [MissingLocationError] if anchor has no expression location
      def s_at(anchor, type, *children)
        expression = anchor.loc&.expression
        raise MissingLocationError, "anchor #{anchor.type} node has no source location" unless expression

        s(type, *children, location: ::Parser::Source::Map.new(expression))
      end

      # The low-level reordering primitive. Thunking is the one reordering lever: text never moves and execution can
      # only move later, so "hoist A above B" is expressed as "run B after A". Returns a single Thunk node: splice it
      # where the statements must RUN — statement position or composed inside an expression, e.g. as an assert_raises
      # block body. The wrapped statements keep their own locs, and the lowering derives the hidden proc's textual
      # placement from them, so the body still emits on its source lines even though execution waits. Reuse the same
      # node to execute one body from several points.
      #
      # Semantics are near-transparent (see ThunkLowering): +return+ still returns from the enclosing method
      # (non-lambda proc), and locals the wrapped statements assign stay method-scope (pre-declared before the proc).
      # Jump keywords whose owner lies outside the wrapped statements keep Ruby's native behavior — +break+/+retry+
      # fail loudly at the jump's own source line, +next+/+redo+ silently end or restart the thunk body. Weigh that
      # when choosing what your surface thunks.
      #
      # Prefer +run_after+ when the execution point sits in the same statement sequence as the statements.
      #
      # @param statements [Array<Parser::AST::Node>] statements to wrap
      # @return [ASTTransform::Thunk] the thunk node
      def thunk(*statements)
        s(:ast_thunk, Thunk::Id.new, *statements)
      end

      # The paved road for execution reordering in flat statement sequences. Named for the constraint, not the
      # mechanism — with text pinned to source lines the only physical lever is delaying execution, so "run X after
      # Y" is the constraint an author states. Returns a NEW sequence in which the +run+ statements are removed and a
      # thunk wrapping them is inserted immediately after +after+.
      #
      # All membership checks are by identity (equal?), never ==: node equality ignores location, so two textually
      # identical statements on different lines compare == and value matching could splice the wrong one.
      #
      # @param statements [Array<Parser::AST::Node>] the sequence being composed
      # @param run [Array<Parser::AST::Node>] contiguous run of elements of +statements+ (by identity) whose
      #   execution must wait
      # @param after [Parser::AST::Node] element of +statements+ (by identity, not inside +run+) the +run+ statements
      #   execute after
      # @return [Array<Parser::AST::Node>] new sequence with the thunk placed
      # @raise [ArgumentError] if +run+ is not a contiguous identity-run of +statements+, or +after+ is not an
      #   element (or is inside +run+)
      def run_after(statements, run:, after:)
        run_range = contiguous_identity_range(statements, run)
        raise ArgumentError, "run: must be a contiguous run of elements of statements (by identity)" unless run_range

        after_index = statements.index { |statement| statement.equal?(after) }
        raise ArgumentError, "after: must be an element of statements (by identity)" unless after_index
        raise ArgumentError, "after: cannot be inside run:" if run_range.cover?(after_index)

        reordered = statements.dup
        reordered[run_range] = []

        insertion_index = reordered.index { |statement| statement.equal?(after) }
        reordered.insert(insertion_index + 1, thunk(*run))
      end

      private

      # The range +members+ occupies in +sequence+, or nil unless members is a non-empty contiguous identity-run in
      # order.
      def contiguous_identity_range(sequence, members)
        return nil if members.empty?

        start = sequence.index { |element| element.equal?(members.first) }
        return nil unless start

        contiguous = members.each_with_index.all? do |member, offset|
          sequence[start + offset]&.equal?(member)
        end

        contiguous ? (start...(start + members.size)) : nil
      end
    end
  end
end

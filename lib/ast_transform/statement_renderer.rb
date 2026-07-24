# frozen_string_literal: true

require 'unparser'

module ASTTransform
  # Renders individual statements to text via Unparser, working around the two consequences of unparsing them in
  # isolation (line-aligned emission places each statement independently, so each is ripped out of its context):
  #
  # * Isolation loses the surrounding scope's local variables, making Unparser re-parse identifiers as method calls
  #   and fail its dstr round-trip verification — so a renderer is built once per tree with every local bound
  #   anywhere in it, and feeds Unparser that set on each render.
  # * Unparser normalizes some single-line constructs into multi-line form, which would push following statements
  #   off their lines — so renders taller than their source are compressed back to one line when safely possible.
  #
  # Immutable: configured with the tree's locals at construction, no per-render state.
  class StatementRenderer
    # Node types that bind a local variable name: assignments plus every method/block parameter flavor.
    LOCAL_BINDING_TYPES = [:lvasgn, :arg, :optarg, :restarg, :kwarg, :kwoptarg, :blockarg, :shadowarg].freeze

    class << self
      # Builds a renderer for statements of +node+'s tree, holding every local bound anywhere in it — an
      # over-approximation that is safe because the set only informs Unparser's re-parse verification, never the
      # rendered text.
      def for_tree(node)
        new(local_variables: collect_local_variables(node))
      end

      private

      def collect_local_variables(node, names = Set.new)
        return names unless node.is_a?(::Parser::AST::Node)

        names << node.children[0] if LOCAL_BINDING_TYPES.include?(node.type) && node.children[0]
        node.children.each { |child| collect_local_variables(child, names) }
        names
      end
    end

    # @param local_variables [Set<Symbol>] every local bound in the tree the statements come from.
    def initialize(local_variables:)
      @local_variables = local_variables
    end

    # @param node [Parser::AST::Node] the statement to render.
    # @return [String] Unparser's render, informed of the tree's locals.
    def unparse(node)
      Unparser.unparse(node, static_local_variables: @local_variables)
    end

    # Renders +node+ no taller than its source when safely possible. Unparser normalizes some single-line
    # constructs into multi-line form (e.g. modifier-if into if/end); when the render is taller than the
    # statement's source, compress it back to one line — verified by re-parse so a statement that cannot be safely
    # single-lined (e.g. containing a heredoc) falls back to its multi-line render.
    def aligned_render(node)
      render = unparse(node)
      loc = node.loc
      return render unless loc.respond_to?(:last_line) && loc.line

      source_height = loc.last_line - loc.line + 1
      return render if render.count("\n") < source_height

      compress_to_single_line(render) || render
    end

    private

    def compress_to_single_line(render)
      candidate = render.split("\n").map(&:strip).join('; ')
      # Both sides parsed without scope context, so lvar/send ambiguity cancels out; equality means the newline
      # join preserved structure.
      Unparser.parse(candidate) == Unparser.parse(render) ? candidate : nil
    rescue Parser::SyntaxError
      nil
    end
  end
end

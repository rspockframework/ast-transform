# frozen_string_literal: true

require "ast_transform/abstract_processor"

module ASTTransform
  # Base class for structural transformations: subclass and write +on_*+ handlers to rewrite a pattern wherever it
  # occurs in the tree. This is one of three authoring shapes — pick by how the rewrite site is found:
  #
  # - Structural (this class): the pattern alone identifies the site, so +on_*+ handlers rewrite it anywhere in
  #   the tree.
  # - Positional (node builders): a plain object with +run(node) → node+, including only TransformationHelper. The
  #   caller owns traversal and applies the builder at a site it already located; the builder never walks. Anything
  #   with that duck type composes with Transformer and other passes — deriving from this class is just one way to
  #   implement it.
  # - Sibling-annotation: the pattern is a marker statement plus its NEXT sibling, matched in +process_node+ where
  #   the child list is visible — an +on_*+ handler sees one node, never its siblings, and cannot delete itself
  #   from its parent. See ASTTransform::Transformation (the +transform!+ detector) for the canonical example.
  #
  # For read-only passes that harvest information instead of rewriting, see ASTTransform::AbstractAnalysis.
  class AbstractTransformation < AbstractProcessor
    # Runs this transformation on +node+ and returns the rebuilt tree.
    # Note: If you want to add one-time checks to the transformation, override this, then call super.
    #
    # @param node [Parser::AST::Node] The node to be transformed.
    #
    # @return [Parser::AST::Node] The transformed node.
    def run(node)
      process(node)
    end
  end
end

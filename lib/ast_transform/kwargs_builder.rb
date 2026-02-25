# frozen_string_literal: true

require 'prism/translation/parser'

module ASTTransform
  # Extends the default Prism parser builder to distinguish keyword arguments
  # from hash literals in the AST.
  #
  # The upstream builder always emits :hash nodes for both `foo(bar: 1)` and
  # `foo({ bar: 1 })`. Unparser uses the node type to decide whether to emit
  # braces: :hash gets `{}`, :kwargs does not. Since Ruby 3.0+ treats these as
  # semantically different (strict keyword/positional separation), we need the
  # AST to preserve the distinction.
  class KwargsBuilder < Prism::Translation::Parser::Builder
    def associate(begin_t, pairs, end_t)
      node = super
      return node unless begin_t.nil? && end_t.nil?

      node.updated(:kwargs)
    end
  end
end

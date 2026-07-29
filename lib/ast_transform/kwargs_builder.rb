# frozen_string_literal: true

require "prism/translation/parser"

module ASTTransform
  # The framework's parser builder: the stock builder with the parser gem's `emit_kwargs` opt-in, which
  # distinguishes keyword arguments from hash literals in the AST.
  #
  # With the flag off (the gem's compatibility default) both `foo(bar: 1)` and `foo({ bar: 1 })` emit :hash nodes.
  # Unparser uses the node type to decide whether to emit braces: :hash gets `{}`, :kwargs does not. Since Ruby 3.0+
  # treats these as semantically different (strict keyword/positional separation), the AST must preserve the
  # distinction. `emit_kwargs` rewrites at the call sites where kwargs semantics live (method calls, index,
  # super/yield); the flag is a class-level ivar, so setting it here opts in this builder only — the global
  # Parser::Builders::Default stays untouched.
  #
  # NOTE: parsed nodes deliberately stay plain Parser::AST::Node. Custom node classes exist only for registered
  # custom types (see ASTTransform::Node), which are IR and never reach Unparser: AST::Node#eql? compares class, and
  # Unparser verifies dynamic-string emission by re-parsing and comparing eql? against the freshly parsed
  # (plain-class) node — custom-class nodes of standard types would fail that verification.
  class KwargsBuilder < Prism::Translation::Parser::Builder
    self.emit_kwargs = true
  end
end

# typed: false
# frozen_string_literal: true

require "prism/translation/parser"

module ASTTransform
  # The framework's parser builder: the stock builder with the parser gem's `modernize` opt-ins, which produce the
  # modern AST (`:procarg0`, `:index`/`:indexasgn`, `:lambda`, `:forward_args`, `:kwargs`, `:match_pattern`, ...).
  #
  # Unparser is written against the modern AST, so parsing in the gem's legacy compatibility shapes changes meaning
  # at emission. Two examples that matter to any transformed source:
  #
  # - Block parameters: in the modern AST `{ |a| }` is `s(:args, s(:procarg0, s(:arg, :a)))`, and a lone bare
  #   `s(:arg)` means the trailing-comma form `{ |a,| }`. The legacy shape for `{ |a| }` is that lone `s(:arg)`, so
  #   Unparser emitted `|a,|` and every one-parameter block auto-splatted its argument (#21).
  # - Keyword arguments: with `emit_kwargs` off, `foo(bar: 1)` and `foo({ bar: 1 })` both parse as :hash; Unparser
  #   braces :hash and not :kwargs, and Ruby 3+ treats the two as different calls.
  #
  # The flags are class-level ivars, so modernizing here opts in this builder only — the global
  # Parser::Builders::Default stays untouched.
  #
  # NOTE: parsed nodes deliberately stay plain Parser::AST::Node. Custom node classes exist only for registered
  # custom types (see ASTTransform::Node), which are IR and never reach Unparser: AST::Node#eql? compares class, and
  # Unparser verifies dynamic-string emission by re-parsing and comparing eql? against the freshly parsed
  # (plain-class) node — custom-class nodes of standard types would fail that verification.
  class ModernBuilder < Prism::Translation::Parser::Builder
    modernize
  end
end

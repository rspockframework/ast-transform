# frozen_string_literal: true

require 'test_helper'
require 'ast_transform/statement_renderer'
require 'ast_transform/transformer'

module ASTTransform
  class StatementRendererTest < Minitest::Test
    extend ASTTransform::Declarative

    def parse(source)
      ASTTransform::Transformer.new.build_ast(source)
    end

    test "unparse renders an isolated statement using locals collected from the whole tree" do
      tree = parse("name = fetch\nmessage = \"hi \#{name}\"\n")
      isolated_dstr_statement = tree.children[1]

      # Without the tree's locals, Unparser's dstr round-trip verification re-parses `name` as a method call and
      # raises; for_tree restores the context the statement was ripped out of.
      rendered = StatementRenderer.for_tree(tree).unparse(isolated_dstr_statement)

      assert_equal "message = \"hi \#{name}\"", rendered
    end

    test "aligned_render compresses a render taller than its source back to one line" do
      statement = parse("raise ArgumentError if strict\n")

      rendered = StatementRenderer.for_tree(statement).aligned_render(statement)

      assert_equal 1, rendered.lines.size, rendered
    end

    test "aligned_render keeps a render that already fits its source height" do
      statement = parse("def risky\n  compute\nend\n")

      rendered = StatementRenderer.for_tree(statement).aligned_render(statement)

      assert_operator rendered.lines.size, :>, 1, rendered
    end

    test "compress_to_single_line declines renders whose single-line join does not parse" do
      renderer = StatementRenderer.for_tree(parse("noop\n"))

      # No current Unparser render joins into invalid syntax (heredocs are normalized to inline strings), so
      # exercise the totality guard directly: rendering must fall back, never raise, whatever future Unparser
      # output looks like.
      assert_nil renderer.send(:compress_to_single_line, "value = <<~TXT\n  hi\nTXT")
    end

    test "for_tree collects assignments and every parameter flavor" do
      tree = parse(<<~HEREDOC)
        assigned = 1
        def a_method(plain, optional = 1, *splat, keyword:, optional_keyword: 2, &block_arg)
        end
        items.map { |item; shadow| item }
      HEREDOC

      renderer = StatementRenderer.for_tree(tree)
      locals = renderer.instance_variable_get(:@local_variables)

      assert_equal Set[:assigned, :plain, :optional, :splat, :keyword, :optional_keyword, :block_arg, :item, :shadow],
        locals
    end
  end
end

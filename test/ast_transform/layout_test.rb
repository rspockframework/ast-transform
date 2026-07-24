# frozen_string_literal: true

require 'test_helper'
require 'ast_transform/layout'

module ASTTransform
  class LayoutTest < Minitest::Test
    extend ASTTransform::Declarative

    test "place pads with blank lines to reach a target line ahead of the cursor" do
      layout = Layout.new
      layout.place(3, 'statement')

      assert_equal "\n\nstatement\n", layout.to_source
    end

    test "place indents a fresh line to the requested column" do
      layout = Layout.new
      layout.place(1, 'statement', column: 2)

      assert_equal "  statement\n", layout.to_source
    end

    test "place packs onto the current line when the cursor has passed the target" do
      layout = Layout.new
      layout.place(1, 'first')
      layout.place(1, 'displaced')

      assert_equal "first; displaced\n", layout.to_source
    end

    test "packed text ignores the column" do
      layout = Layout.new
      layout.place(1, 'first')
      layout.place(1, 'displaced', column: 4)

      assert_equal "first; displaced\n", layout.to_source
    end

    test "loc-less text (nil target) packs onto the current line" do
      layout = Layout.new
      layout.place(1, 'first')
      layout.place(nil, 'synthetic')

      assert_equal "first; synthetic\n", layout.to_source
    end

    test "multi-line text advances the cursor by its height" do
      layout = Layout.new
      layout.place(1, "opener\n  continuation")

      assert_equal 2, layout.cursor
      # Continuation lines keep their own relative indentation.
      assert_equal "opener\n  continuation\n", layout.to_source
    end

    test "emission re-anchors at the next target still ahead of the cursor" do
      layout = Layout.new
      layout.place(1, "tall\ntall\ntall")
      layout.place(2, 'displaced')
      layout.place(5, 'aligned')

      assert_equal "tall\ntall\ntall; displaced\n\naligned\n", layout.to_source
    end

    test "place_on_fresh_line never packs" do
      layout = Layout.new
      layout.place(1, 'statement')
      layout.place_on_fresh_line('ensure')

      assert_equal "statement\nensure\n", layout.to_source
    end

    test "pack onto an empty layout opens the first line" do
      layout = Layout.new
      layout.pack('lonely')

      assert_equal "lonely\n", layout.to_source
    end

    test "cursor reports the line currently being written" do
      layout = Layout.new

      assert_equal 0, layout.cursor

      layout.place(2, 'statement')

      assert_equal 2, layout.cursor
    end
  end
end

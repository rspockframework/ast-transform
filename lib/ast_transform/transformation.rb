# frozen_string_literal: true

require "ast_transform"
require "ast_transform/abstract_transformation"
require "ast_transform/transformer"
require "unparser"

module ASTTransform
  # The +transform!+ detector — the canonical sibling-annotation pass (see AbstractTransformation for the taxonomy).
  # A +transform!(...)+ statement is a pragma on the NEXT sibling: the transformations it names are applied to the
  # following class definition or constant assignment, and the marker itself is deleted from the child list. Both
  # effects need the parent's child list in view, which is why matching happens in +process_node+ — an +on_send+
  # handler would see the marker node alone, with no access to its next sibling and no way to remove itself.
  class Transformation < ASTTransform::AbstractTransformation
    TRANSFORM_AST = s(:send, nil, :transform!)

    private

    def process_node(node)
      children = node.children.map.with_index do |child_node, index|
        previous_sibling = previous_child(node, index)
        process_node_helper(child_node, previous_sibling)
      end

      count_before_reject = children.size

      children.reject!.with_index do |child_node, index|
        transform_node?(child_node) && transformable_node?(next_child(node, index))
      end

      processed = process_all(children)

      if node.type == :begin && processed.size == 1 && children.size < count_before_reject
        processed.first
      else
        node.updated(nil, processed)
      end
    end

    def previous_child(node, index)
      index > 0 ? node.children[index - 1] : nil
    end

    def next_child(node, index)
      index >= 0 ? node.children[index + 1] : nil
    end

    def process_node_helper(node, previous_node)
      if transform_node?(previous_node) && transformable_node?(node)
        transformations = extract_transformations(previous_node)
        ASTTransform::Transformer.new(*transformations).transform_ast(node)
      else
        node
      end
    end

    def transform_node?(node)
      return false unless node.is_a?(Parser::AST::Node)

      node.type == :send && node.children.count >= 3 && node.children[0].nil? && node.children[1] == :transform!
    end

    def transformable_node?(node)
      return false unless node.is_a?(Parser::AST::Node)

      [:class, :casgn].include?(node.type)
    end

    def extract_transformations(node)
      node.children.map do |child_node|
        extract_transformation(child_node)
      end.compact!
    end

    def extract_transformation(node)
      return unless node.is_a?(Parser::AST::Node)
      return if node.children.count < 2

      require_transformation(node)
      code = Unparser.unparse(node)
      # A bare constant reference is instantiated; an explicit .new is kept as written.
      code = "#{code}.new" unless node.children[1] == :new

      TOPLEVEL_BINDING.eval(code)
    end

    def require_transformation(node)
      const_node = node.children.first
      const_name = Unparser.unparse(const_node)

      constant = try_const_get(const_name)
      unless constant
        require_path = require_path(const_name)
        require(require_path)
      end

      nil
    end

    def require_path(const_name)
      acronyms = ASTTransform.acronyms
      acronym_regex = acronyms.empty? ? /(?=a)b/ : /#{acronyms.join("|")}/
      return const_name unless /[A-Z-]|::/.match?(const_name)

      word = const_name.to_s.gsub("::", "/")
      word.gsub!(/(?:(?<=([A-Za-z\d]))|\b)(#{acronym_regex})(?=\b|[^a-z])/) { "#{::Regexp.last_match(1) && "_"}#{::Regexp.last_match(2).downcase}" }
      word.gsub!(/([A-Z\d]+)([A-Z][a-z])/, '\1_\2')
      word.gsub!(/([a-z\d])([A-Z])/, '\1_\2')
      word.tr!("-", "_")
      word.downcase!
      word
    end

    def try_const_get(const_name)
      Object.const_get(const_name)
    rescue NameError
      nil
    end
  end
end

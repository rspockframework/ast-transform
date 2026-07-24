# frozen_string_literal: true

require "parser"

module ASTTransform
  module TransformationHelper
    class << self
      def included(base)
        base.extend(Methods)
        base.include(Methods)
      end
    end

    module Methods
      def s(type, *children, **properties)
        Parser::AST::Node.new(type, children, properties)
      end
    end
  end
end

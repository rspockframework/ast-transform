# frozen_string_literal: true
require 'ast_transform/transformer'
require 'ast_transform/transformation_helper'
require 'string_helper'

module ASTTransform
  module Helpers
    module TransformationHelper
      include ASTTransform::TransformationHelper
      include ASTTransform::Helpers::StringHelper

      def transform(source, *transformations)
        ASTTransform::Transformer.new(*transformations).transform(source)
      end
    end
  end
end

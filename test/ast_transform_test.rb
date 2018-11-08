require "test_helper"

class ASTTransformTest < Minitest::Test
  extend ASTTransform::Declarative

  test "ensure gem has version number" do
    refute_nil ::ASTTransform::VERSION
  end
end

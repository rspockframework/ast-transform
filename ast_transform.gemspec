# frozen_string_literal: true

lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "ast_transform/version"

Gem::Specification.new do |spec|
  spec.name          = "ast_transform"
  spec.version       = ASTTransform::VERSION
  spec.authors       = ["Jean-Philippe Duchesne"]
  spec.email         = ["jpduchesne89@gmail.com"]

  spec.summary       = "An AST transformation framework."
  spec.description   = spec.summary
  spec.homepage      = "https://github.com/rspockframework/ast-transform"
  spec.license       = "MIT"
  spec.files         = %x(git ls-files -z).split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.required_ruby_version = '>= 3.3'

  # Development dependencies
  spec.add_development_dependency("bundler", ">= 2.1")
  spec.add_development_dependency("minitest", "~> 5.14")
  spec.add_development_dependency("minitest-reporters", "~> 1.4")
  spec.add_development_dependency("pry", ">= 0.14")
  spec.add_development_dependency("rake", "~> 13.0")
  # rubocop-shopify >= 3.0 requires Ruby >= 3.3; bump alongside our own floor.
  spec.add_development_dependency("rubocop-shopify", "~> 2.18")
  spec.add_development_dependency("simplecov", "~> 0.22")

  # Runtime dependencies
  # parser provides the runtime AST vocabulary (Parser::AST::Node/Processor,
  # Source::Buffer/Map); parsing itself goes through prism's translation layer.
  spec.add_runtime_dependency "parser", ">= 3.3"
  spec.add_runtime_dependency "prism", ">= 1.5"
  # unparser >= 0.8: static_local_variables: (0.7 interface) + the prism-based
  # round-trip verification parser required for Ruby >= 3.4 syntax.
  spec.add_runtime_dependency "unparser", ">= 0.8"
end

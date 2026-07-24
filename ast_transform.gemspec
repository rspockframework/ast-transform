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

  # Development dependencies live in the Gemfile (Gemspec/DevelopmentDependencies).

  # Runtime dependencies
  # parser provides the runtime AST vocabulary (Parser::AST::Node/Processor,
  # Source::Buffer/Map); parsing itself goes through prism's translation layer.
  spec.add_runtime_dependency "parser", ">= 3.3"
  spec.add_runtime_dependency "prism", ">= 1.5"
  # unparser >= 0.8: static_local_variables: (0.7 interface) + the prism-based
  # round-trip verification parser required for Ruby >= 3.4 syntax.
  spec.add_runtime_dependency "unparser", ">= 0.8"
end

[![CI](https://github.com/rspockframework/ast-transform/actions/workflows/ci.yml/badge.svg)](https://github.com/rspockframework/ast-transform/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/rspockframework/ast-transform/branch/master/graph/badge.svg)](https://codecov.io/gh/rspockframework/ast-transform)

# ASTTransform

ASTTransform is an Abstract Syntax Tree (AST) transformation framework. It hooks into the compilation process and allows to perform AST transformations using an annotation: `transform!`.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ast_transform'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install ast_transform

Add this to the very beginning of your script or application to install the ASTTransform hook:

```ruby
require 'ast_transform'
ASTTransform.install
```

### Compatibility with Bootsnap

ASTTransform is compatible with [Bootsnap](https://github.com/Shopify/bootsnap/). The only requirement is to install the above hook after Bootsnap, and ASTTransform does the rest for you.

## Usage

Getting started using ASTTransform is extremely easy! All you need is to use the `transform!` annotation:

```ruby
transform!(MyTransformation)
class MyClass
  # ...
end
```

When your class is required and loaded into the runtime, ASTTransform will run the `MyTransformation` transformation on the annotated code.

### Supported annotated code

The following expressions can be annotated, which will pass only the annotated AST node to the transformation:

#### Class definitions

```ruby
transform!(MyTransformation)
class Foo
  # ...
end
```

#### Constant assignments

```ruby
transform!(MyTransformation)
Foo = Class.new do
  # ...
end
```

### Running multiple transformations

#### On the same AST node

You can run multiple transformations on the same code, by passing multiple transformations to the annotation:

```ruby
transform!(MyTransformation1, MyTransformation2)
class Foo
  # ...
end
```

**Note**: The transformations will be executed in order, the output of the previous transformation being fed into the next, etc...

#### On different AST nodes

Because each `transform!` annotation runs transformations in isolated scope, it is possible to have multiple annotated nodes in the same file:

```ruby
transform!(MyTransformation)
class Foo
  # ...
end

transform!(MyTransformation)
class Bar
  # ...
end
```

You can even have nested `transform!` annotations:

```ruby
transform!(FooTransformation)
class Foo
  transform!(BarTransformation)
  class Bar
    # ...
  end

  # ...
end
```

The above code would first process class `Foo` using `FooTransformation` (which could even make modifications to `Bar` on its own), and then `BarTransformation` would be run against `Bar`.

### Writing Transformations

For more in-depth information regarding processing AST nodes, we recommend looking at https://github.com/whitequark/ast, as transformations are built on top of `Parser::AST::Processor`, which in turn is built on top of the `ast` gem.

Transformations should derive from `ASTTransform::AbstractTransformation`:

```ruby
require 'ast_transform/abstract_transformation'

class MyTransformation < ASTTransformation::AbstractTransformation
  # ...
end
```

#### Transformation discoverability

ASTTransform automatically loads your transformations at compile time. As such, we expect your files to be located at a known path.

Transformations are required using the following scheme, i.e. for `MyNamespace::MyTransformation`, it will make the following call, so your file must be placed accordingly for ASTTransform to find it:
```ruby
require 'my_namespace/my_transformation'
```

#### Processing each node

To do some processing on each node, override the `process_node` private method. If you do this, make sure to also process the children nodes if required.

```ruby
require 'ast_transform/abstract_transformation'

class MyTransformation < ASTTransformation::AbstractTransformation
  private

  def process_node(node)
    # ... processing
    node.updated(nil, process_all(node.children))
  end
end
```

In the above, `node#updated` allows updating the node, either its type or its children. Each node is immutable, so updating nodes requires recursively re-creating the tree from the deepest modified nodes. Passing `nil` as the first argument keeps the same node type.

#### Processing on certain types of nodes only

The [ast gem](https://github.com/whitequark/ast) uses a pattern in which a Transformation may implement a method matching a node type, i.e. `on_class`, `on_send`, `on_lvar`, etc... This is very useful when transformations should process all nodes of this type.

### Parameterizable transformations

If you want your transformation to be customizable, accept the parameters in the constructor. The annotation can the be changed accordingly:

```ruby
class FooTransformation < ASTTransform::AbstractTransformation
  def initialize(param1, params2: false)
    # ...
  end

  # ...
end

transform!(FooTransformation.new(param1, param2: true))
class Foo
  # ...
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Releasing a New Version

There are two ways to create a release. Both require that `version.rb` has already been updated and merged to main.

### Via GitHub UI

1. Update `VERSION` in `lib/ast_transform/version.rb` and run `bundle install` to regenerate `Gemfile.lock`, commit, open a PR, and merge to main
2. Go to the repo on GitHub → **Releases** → **Draft a new release**
3. Enter a new tag (e.g. `v2.0.0`), select `main` as the target branch
4. Add a title and release notes (GitHub can auto-generate these from merged PRs)
5. Click **Publish release**

### Via CLI

1. Update `VERSION` in `lib/ast_transform/version.rb` and run `bundle install` to regenerate `Gemfile.lock`, commit, open a PR, and merge to main
2. Tag and push:
   ```
   git checkout main && git pull
   git tag v2.0.0
   git push origin v2.0.0
   ```

In both cases, the [release workflow](.github/workflows/release.yml) validates that the tag matches `version.rb`, builds the gem, and publishes it to [rubygems.org](https://rubygems.org) via [Trusted Publishing](https://guides.rubygems.org/trusted-publishing/) (no API key needed). If there's a mismatch, the workflow fails before publishing.

### One-time setup

Configure the gem as a trusted publisher on rubygems.org so that the release workflow can publish automatically. See the [Trusted Publishing guide](https://guides.rubygems.org/trusted-publishing/pushing-a-new-gem-with-a-trusted-publisher/) for details.

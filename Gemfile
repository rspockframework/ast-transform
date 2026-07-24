# frozen_string_literal: true

source "https://rubygems.org"

git_source(:github) { |repo_name| "https://github.com/#{repo_name}" }

# Specify your gem's dependencies in ast_transform.gemspec
gemspec

# Transitive dependency of rubocop: parallel >= 2 requires Ruby >= 3.3, but we
# still support 3.2. Drop this pin when our Ruby floor moves to 3.3.
gem "parallel", "< 2", require: false

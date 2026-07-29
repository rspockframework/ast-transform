# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.1.0] - 2026-07-29
### Added
- Analysis passes: `ASTTransform::AbstractAnalysis`, the read-only counterpart of `AbstractTransformation`. Both leaves share the extracted traversal core `ASTTransform::AbstractProcessor` (sealed `process`, `process_node` hook, thunk descent, `TransformationHelper`) and differ only in what `run` returns — the rebuilt tree for transformations, the analysis instance (result readers) for analyses.
- Public parse entry: `ASTTransform.parse(source, file_path:)` / `ASTTransform.parse_file(path)` expose the framework's Prism-backed parsing to analysis-only consumers that never emit. `ASTTransform::SourceParser` owns the parsing seam; `Transformer#build_ast` / `#build_ast_from_file` delegate to it (unchanged public behavior).
- Pass-taxonomy documentation on `AbstractTransformation`, `Transformation`, and the README: structural (`on_*` handlers, pattern matched anywhere), positional (node builders with the bare `run(node) → node` duck type, caller owns traversal), and sibling-annotation (marker statement + next sibling, matched in `process_node` where the child list is visible — `transform!` itself).

## [3.0.0] - 2026-07-24
### Added
- Line-aligned emission: transformed code is emitted with every loc-carrying statement on its original source line, making backtraces, breakpoints, and debugger display correct by construction (`LineAlignedEmitter`).
- Authoring toolkit in `TransformationHelper`: `s_at` (loc-anchored node construction), `thunk` (a single invariant-checked `Thunk` node spliced at the execution point; the lowering derives the hidden proc's textual placement from the body's source locations), and `run_after` (sequence-level execution reordering that preserves textual/source order). Thunks lower to a non-lambda proc, so `return` still returns from the enclosing method, and locals assigned by thunked statements are pre-declared to stay method-scope. Reusing one thunk node executes its body from several points.
- `ASTTransform::Node.register`: type-routed construction of custom IR node classes through `s`, with an emitter postcondition (`LineAlignedEmitter::UnloweredNodeTypeError`) rejecting custom types that were not lowered before emission.
- `ast_transform/testing/assertions` (test-only): `assert_line_aligned` and `assert_backtrace_lines` for transform authors' suites.
- Error types, each owned by its producer: `TransformationHelper::MissingLocationError`, `ThunkLowering::PlacementError`, `LineAlignedEmitter::UnloweredNodeTypeError`. Thunk construction invariants raise plain `ArgumentError`.

### Removed
- **Breaking:** `ASTTransform::SourceMap` and source-map registration. Line-aligned emission makes raw VM line numbers the source line numbers, so there is nothing left to map at display time.

### Changed
- **Breaking:** `Transformer#transform` and `#transform_file_source` emit line-aligned output (source-anchored layout, always newline-terminated) instead of Unparser's re-normalized formatting.
- **Breaking:** dropped Ruby 3.2 support (EOL since March 2026); `required_ruby_version` is now `>= 3.3`.
- Dependency floors now reflect reality: `unparser >= 0.8` (the emitter uses `static_local_variables:`, a 0.7 interface, and 0.8's prism-based round-trip verification is required for Ruby >= 3.4 syntax) and `parser >= 3.3` (unparser's own floor; the declared `>= 3.0` could never resolve lower).

## [0.1.4] 2019-06-20
### Fixed
- Source mapping for transformations wrapping source nodes into virtual nodes now work.

## [0.1.3] 2019-05-28
### Added
- Changing the output path for transformed files is now supported through `ASTTransform.output_path=`.

## [0.1.2] 2018-12-21
### Fixed
- Bumped and relaxed Unparser dependency to ~> 0.4

## [0.1.1] 2018-12-06
### Added
- ASTTransform::Transformer now supports passing a custom AST::Node Builder.

## [0.1.0] 2018-11-08
### Initial Release!
# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.0] - Unreleased
### Added
- Line-aligned emission: transformed code is emitted with every loc-carrying statement on its original source line, making backtraces, breakpoints, and debugger display correct by construction (`LineAlignedEmitter`).
- Authoring toolkit in `TransformationHelper`: `s_at` (loc-anchored node construction), `defer` (deferred-execution marker pairs with a control-flow guard), and `run_after` (sequence-level execution reordering that preserves textual/source order).
- `ASTTransform::Node.register`: type-routed construction of custom IR node classes through `s`, with an emitter postcondition (`UnloweredNodeTypeError`) rejecting custom types that were not lowered before emission.
- `ast_transform/test_helpers` (test-only): `assert_line_aligned` and `assert_backtrace_lines` for transform authors' suites.
- Error types: `MissingLocationError`, `NonDeferrableError`, `UnmatchedDeferralError`, `UnloweredNodeTypeError`.

### Removed
- **Breaking:** `ASTTransform::SourceMap` and source-map registration. Line-aligned emission makes raw VM line numbers the source line numbers, so there is nothing left to map at display time.

### Changed
- **Breaking:** `Transformer#transform` and `#transform_file_source` emit line-aligned output (source-anchored layout, always newline-terminated) instead of Unparser's re-normalized formatting.

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
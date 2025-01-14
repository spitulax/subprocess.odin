# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Exec_Opts.cwd`: Sets the working directory of process.
- `pipe_read_non_append`: Reads from a pipe to a slice.
- `command_set`: Sets the arguments of `Command`.
- Creating pipes manually and using them for processes. See examples.

### Fixed

- `pipe_write_buf` and `pipe_write_string` now return uint. (Breaking)

## [0.1.0] - 2024-12-23

### Added

- Initial release.

[Unreleased]: https://github.com/spitulax/subprocess.odin/compare/0.1.0...HEAD
[0.1.0]: https://github.com/spitulax/subprocess.odin/releases/tag/0.1.0

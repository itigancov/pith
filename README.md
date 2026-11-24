# Pith

[![test](https://github.com/itigancov/pith/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/itigancov/pith/actions/workflows/test.yml)

A live-Markdown note editor for macOS, built on NSTextView and TextKit 2.

**Status:** pre-release, not yet installable.

## Requirements

- macOS 14+
- To build: Xcode 27 and [`xcodegen`](https://github.com/yonaskolb/XcodeGen)

## Development

- `make test` — run the package tests
- `make build` — generate the Xcode project and build `Pith.app`
- `make run` — build and open `Pith.app` (`FIXTURE=<path>` for another text)
- `make bench` — restyle timings on a generated 5k-line note

## License

[MIT](LICENSE)

set shell := ["zsh", "-cu"]

default: build

# Build everything in debug mode.
build:
    swift build

# Run every test suite, including the vendored UI package's.
test:
    swift test
    swift test --package-path Vendor/SwiftTUI

# Rewrite sources with the formatter.
format:
    swift format --in-place --recursive --parallel Sources Tests Package.swift

# Fail if any file is not formatted.
format-check:
    swift format lint --strict --recursive --parallel Sources Tests Package.swift

lint:
    swiftlint lint --strict --quiet

# The only package dependency must be the vendored UI library.
deps-check:
    #!/usr/bin/env zsh
    set -euo pipefail
    deps=$(swift package show-dependencies --format flatlist | grep -v '^ytm-cli$' || true)
    if [[ "$deps" != "swifttui" ]]; then
        echo "unexpected dependencies:"; echo "$deps"; exit 1
    fi
    echo "dependencies: swifttui (vendored) only"

precommit: format-check lint deps-check build test

# Release build, ad-hoc signed, installed to ~/.local/bin/ytm.
install:
    #!/usr/bin/env zsh
    set -euo pipefail
    swift build -c release
    mkdir -p ~/.local/bin
    cp .build/release/ytm ~/.local/bin/ytm
    codesign --force --sign - ~/.local/bin/ytm
    echo "installed ~/.local/bin/ytm"

doctor:
    swift run ytm doctor

# Drive the real binary through a pseudo-terminal (needs network, plays audio).
smoke: build
    python3 -I Scripts/tui-smoke.py .build/debug/ytm

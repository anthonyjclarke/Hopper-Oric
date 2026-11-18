# Hopper — recipes. The builds themselves are the Makefile (make verify, make c64, make c64-run, make c64-smoke).

default:
    @just --list

# Build and verify the Oric tape.
build:
    make verify

# Build the C64 .prg and the scripted test build.
c64:
    make c64-smoke

# --- Documentation (docs/html_documentation.md). The figure tools need Pillow: DOCS_PYTHON, else python3.14 (Homebrew), else python3.
docs_py := `echo "${DOCS_PYTHON:-$(command -v python3.14 || echo python3)}"`

# Everything: build both, capture the screens, decode the figures, generate docs/HOPPER.html.
docs: build c64
    {{docs_py}} docs/tools/capture_screens.py
    {{docs_py}} docs/tools/render_graphics.py
    {{docs_py}} docs/tools/render_oric.py
    {{docs_py}} docs/tools/render_enhanced.py
    node docs/tools/build_docs.mjs

# Regenerate docs/HOPPER.html from the Markdown and the current images only.
docs-html:
    node docs/tools/build_docs.mjs

# Fail if a chapter names a missing label or the saved handbook is stale.
docs-check: docs-names
    node docs/tools/build_docs.mjs --check

# Regenerate the handbook whenever a source changes.
docs-watch:
    node docs/tools/build_docs.mjs --watch

# Re-capture the VICE screenshots of the C64 build.
docs-screens: c64
    {{docs_py}} docs/tools/capture_screens.py

# Re-render the figures decoded from the Oric tape (deterministic).
docs-graphics: build
    {{docs_py}} docs/tools/render_graphics.py
    {{docs_py}} docs/tools/render_oric.py
    {{docs_py}} docs/tools/render_enhanced.py

# Fail if a chapter names a label that is not in the source.
docs-names:
    python3 docs/tools/doc_names.py

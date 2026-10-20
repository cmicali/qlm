# qlm build helpers. qlm.xcodeproj is generated from project.yml by XcodeGen.

CONFIG ?= Release

.PHONY: help setup project build cli test open clean

# Install the dev-tool dependencies (xcodegen) from the Brewfile.
setup:
	brew bundle

# List every target with the first sentence of the comment block above it.
# A target with no comment of its own prints with an empty description.
help:
	@awk ' \
	    /^#/ { if (!inblock) { text = ""; done = 0 } inblock = 1; \
	           line = $$0; sub(/^# ?/, "", line); \
	           if (line == "" || line ~ /^ /) done = 1; \
	           else if (!done) text = text (text == "" ? "" : " ") line; next } \
	    { inblock = 0 } \
	    /^$$/ { text = "" } \
	    /^[a-z][a-z0-9-]*:/ && !/^[^:]*:[^=]*=/ { \
	        name = substr($$0, 1, index($$0, ":") - 1); \
	        if (!(name in seen)) { seen[name] = 1; names[++n] = name; \
	            if (match(text, /\. /)) text = substr(text, 1, RSTART); \
	            desc[name] = text; if (length(name) > width) width = length(name) } \
	        text = "" } \
	    END { for (i = 1; i <= n; i++) printf "  %-" width "s  %s\n", names[i], desc[names[i]] } \
	' $(MAKEFILE_LIST)

# Fetch vibe-libs at its pinned commit, then generate qlm.xcodeproj from project.yml.
project:
	git submodule update --init --recursive
	xcodegen generate

# The menu bar app. ARGS reaches xcodebuild.
build: project
	xcodebuild -project qlm.xcodeproj -scheme qlm -configuration $(CONFIG) \
	    -derivedDataPath build/DerivedData $(ARGS) build

# The command-line tool, qlmctl.
cli: project
	xcodebuild -project qlm.xcodeproj -scheme qlmctl -configuration $(CONFIG) \
	    -derivedDataPath build/DerivedData $(ARGS) build

# The unit tests, in Debug.
test: project
	xcodebuild -project qlm.xcodeproj -scheme qlm -configuration Debug \
	    -derivedDataPath build/DerivedData $(ARGS) test

# Open the generated project in Xcode.
open: project
	open qlm.xcodeproj

# Remove build output and the generated project.
clean:
	rm -rf build qlm.xcodeproj

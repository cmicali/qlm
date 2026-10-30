# qlm build helpers. qlm.xcodeproj is generated from project.yml by XcodeGen.

CONFIG ?= Release
# The build number is the commit count, so a later commit builds a higher one.
# project.yml holds the marketing version.
BUILD_NUMBER ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)

# make install puts qlm.app in $(DESTDIR)/Applications, and qlmctl in
# $(DESTDIR)$(BINDIR), which needs no sudo. DESTDIR stages a copy elsewhere.
BINDIR ?= $(HOME)/.local/bin
APPDIR = $(DESTDIR)/Applications
# A valid Apple Development identity if the keychain has one, else ad hoc.
# A stable identity keeps macOS's grants, such as Documents access, across
# installs. SIGN_IDENTITY=- signs ad hoc.
SIGN_IDENTITY ?= $(if $(shell security find-identity -v -p codesigning 2>/dev/null \
    | grep '"Apple Development: ' | grep -v CSSMERR_),Apple Development,-)
SIGNED_AS = $(if $(filter -,$(SIGN_IDENTITY)),ad hoc,as $(SIGN_IDENTITY))
PRODUCTS = build/DerivedData/Build/Products/Release

.PHONY: help setup project build cli test install uninstall open clean

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
	    -derivedDataPath build/DerivedData CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) $(ARGS) build

# The command-line tool, qlmctl.
cli: project
	xcodebuild -project qlm.xcodeproj -scheme qlmctl -configuration $(CONFIG) \
	    -derivedDataPath build/DerivedData CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) $(ARGS) build

# The unit tests, in Debug.
test: project
	xcodebuild -project qlm.xcodeproj -scheme qlm -configuration Debug \
	    -derivedDataPath build/DerivedData $(ARGS) test

# Build qlm.app and qlmctl in Release, sign them, and install them. A qlm
# running from $(APPDIR) is asked to quit first, and never killed. Xcode
# adds get-task-allow to a build signed for development, even in Release,
# so the install leaves Xcode's base entitlements out.
install: project
	xcodebuild -project qlm.xcodeproj -scheme qlm -configuration Release \
	    -derivedDataPath build/DerivedData CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) \
	    CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO $(ARGS) build
	xcodebuild -project qlm.xcodeproj -scheme qlmctl -configuration Release \
	    -derivedDataPath build/DerivedData CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) \
	    CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO $(ARGS) build
	codesign --verify --strict $(PRODUCTS)/qlm.app $(PRODUCTS)/qlmctl
	tools/quit-app.sh "$(APPDIR)/qlm.app"
	mkdir -p "$(APPDIR)" "$(DESTDIR)$(BINDIR)"
	rm -rf "$(APPDIR)/qlm.app"
	ditto $(PRODUCTS)/qlm.app "$(APPDIR)/qlm.app"
	install -m 755 $(PRODUCTS)/qlmctl "$(DESTDIR)$(BINDIR)/qlmctl"
	@plist="$(APPDIR)/qlm.app/Contents/Info.plist"; \
	    echo "Installed qlm $$(plutil -extract CFBundleShortVersionString raw -o - "$$plist")" \
	    "($$(plutil -extract CFBundleVersion raw -o - "$$plist")), signed $(SIGNED_AS), in $(APPDIR)," \
	    "and qlmctl in $(DESTDIR)$(BINDIR)."

# Ask qlm to quit, then remove qlm.app and qlmctl. The settings stay.
uninstall:
	tools/quit-app.sh "$(APPDIR)/qlm.app"
	rm -rf "$(APPDIR)/qlm.app"
	rm -f "$(DESTDIR)$(BINDIR)/qlmctl"

# Open the generated project in Xcode.
open: project
	open qlm.xcodeproj

# Remove build output and the generated project.
clean:
	rm -rf build qlm.xcodeproj

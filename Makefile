PREFIX ?= /usr/local
BINDIR := $(PREFIX)/bin
ZSHDIR := $(PREFIX)/share/zsh/site-functions
BINARY := .build/release/hmectl
SOURCES := Sources Tests Package.swift

.PHONY: build test lint format install uninstall clean

# Ad-hoc signature with the hardened runtime, which blocks library injection and debugger attachment.
build:
	swift build -c release
	codesign --force --sign - --options runtime --identifier hmectl $(BINARY)

test:
	swift test

lint:
	swift format lint --strict --recursive $(SOURCES)
	zsh -n completions/_hmectl

format:
	swift format format --in-place --recursive $(SOURCES)

# Copies only, so `sudo make install` never compiles as root.
install:
	@test -x $(BINARY) || { echo "Run 'make build' first." >&2; exit 1; }
	install -d "$(BINDIR)" "$(ZSHDIR)"
	install -m 0755 $(BINARY) "$(BINDIR)/hmectl"
	install -m 0644 completions/_hmectl "$(ZSHDIR)/_hmectl"

uninstall:
	rm -f "$(BINDIR)/hmectl" "$(ZSHDIR)/_hmectl"

clean:
	swift package clean

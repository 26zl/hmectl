PREFIX ?= /usr/local
BINDIR := $(PREFIX)/bin
ZSHDIR := $(PREFIX)/share/zsh/site-functions
BINARY := .build/release/hmectl
SOURCES := Sources Tests Package.swift
CLT_TESTING := /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
# Swift 6.4 in the Command Line Tools does not find the Swift Testing macros by itself.
USES_CLT_TESTING = $(and $(filter /usr/bin/swift,$(shell command -v swift)),$(filter \
	/Library/Developer/CommandLineTools/%,$(shell xcrun --find swift 2>/dev/null)),$(wildcard $(CLT_TESTING)))

.PHONY: build test lint format install uninstall clean

# Ad-hoc signature with the hardened runtime, which blocks library injection and debugger attachment.
build:
	swift build -c release
	codesign --force --sign - --options runtime --identifier hmectl $(BINARY)

test:
	swift test $(if $(USES_CLT_TESTING),-Xswiftc -plugin-path -Xswiftc $(CLT_TESTING)) $(ARGS)

lint:
	swift format lint --strict --recursive $(SOURCES)
	zsh -n completions/_hmectl

format:
	swift format format --in-place --recursive $(SOURCES)

# Copies only, so `sudo make install` never compiles as root.
install:
	@test -x $(BINARY) || { echo "Run 'make build' first." >&2; exit 1; }
	@codesign --display --verbose $(BINARY) 2>&1 | grep -q 'flags=0x[0-9a-f]*([^)]*runtime' \
		|| { echo "$(BINARY) is not signed with the hardened runtime. Run 'make build' first." >&2; exit 1; }
	install -d "$(BINDIR)" "$(ZSHDIR)"
	install -m 0755 $(BINARY) "$(BINDIR)/hmectl"
	install -m 0644 completions/_hmectl "$(ZSHDIR)/_hmectl"
	@if [ "$$(id -u)" = 0 ] && [ -n "$$(find "$(BINDIR)" -maxdepth 0 \( ! -user root -o -perm -020 -o -perm -002 \))" ]; \
	then echo "warning: users other than root can write to $(BINDIR), so a program running as one of them can replace hmectl." >&2; fi

uninstall:
	rm -f "$(BINDIR)/hmectl" "$(ZSHDIR)/_hmectl"

clean:
	swift package clean

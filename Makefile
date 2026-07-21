.PHONY: build test app install uninstall clean

# swift test requires Xcode's XCTest, which Command Line Tools alone does not
# ship. Point at Xcode when xcode-select isn't already pointed there.
DEVELOPER_DIR ?= $(shell test -d /Applications/Xcode.app/Contents/Developer && echo /Applications/Xcode.app/Contents/Developer)
export DEVELOPER_DIR

build:
	/usr/bin/swift build

test:
	/usr/bin/swift test

app:
	./scripts/build-app.sh

install:
	./scripts/install-local.sh

uninstall:
	./scripts/uninstall.sh

clean:
	/usr/bin/swift package clean

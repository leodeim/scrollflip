APP     := ScrollFlip.app
LABEL   := com.leodeim.scrollflip
DEST    := $(HOME)/Applications/$(APP)
MINOS   := $(shell plutil -extract LSMinimumSystemVersion raw Info.plist)
VERSION ?= $(shell plutil -extract CFBundleShortVersionString raw Info.plist)
ARCHS   := arm64 x86_64

.PHONY: build dmg run install uninstall restart logs clean FORCE

build: build/$(APP)

# Rewritten only when VERSION changes, so a new version forces a rebuild.
build/version: FORCE
	@mkdir -p build && echo $(VERSION) | cmp -s - $@ || echo $(VERSION) > $@

build/$(APP): Sources/main.swift Info.plist build/version
	rm -rf $@
	mkdir -p $@/Contents/MacOS
	for arch in $(ARCHS); do \
		swiftc -O -target $$arch-apple-macos$(MINOS) $(SWIFTFLAGS) -o build/scrollflip-$$arch Sources/main.swift || { rm -rf $@; exit 1; }; \
	done
	lipo -create -output $@/Contents/MacOS/scrollflip $(ARCHS:%=build/scrollflip-%)
	cp Info.plist $@/Contents/Info.plist
	plutil -replace CFBundleShortVersionString -string $(VERSION) $@/Contents/Info.plist
	codesign --force --sign - --identifier $(LABEL) $@

dmg: build
	rm -rf build/dmg build/ScrollFlip-*.dmg
	mkdir build/dmg
	cp -R build/$(APP) build/dmg/
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname ScrollFlip -srcfolder build/dmg -format UDZO build/ScrollFlip-$(VERSION).dmg
	rm -rf build/dmg

run: build
	build/$(APP)/Contents/MacOS/scrollflip

install: build
	-pkill -x scrollflip
	mkdir -p $(HOME)/Applications
	rm -rf $(DEST) && cp -R build/$(APP) $(DEST)
	open $(DEST)

uninstall:
	-pkill -x scrollflip
	rm -rf $(DEST)

restart:
	-pkill -x scrollflip
	open $(DEST)

logs:
	log stream --predicate 'subsystem == "$(LABEL)"'

clean:
	rm -rf build

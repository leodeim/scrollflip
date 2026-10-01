APP     := ScrollFlip.app
LABEL   := com.leodeim.scrollflip
DEST    := $(HOME)/Applications/$(APP)
AGENT   := $(HOME)/Library/LaunchAgents/$(LABEL).plist
BIN     := $(DEST)/Contents/MacOS/scrollflip
MINOS   := $(shell plutil -extract LSMinimumSystemVersion raw Info.plist)

.PHONY: build run install uninstall restart logs clean

build: build/$(APP)

build/$(APP): Sources/main.swift Info.plist
	rm -rf $@
	mkdir -p $@/Contents/MacOS
	swiftc -O -target $(shell uname -m)-apple-macos$(MINOS) $(SWIFTFLAGS) -o $@/Contents/MacOS/scrollflip Sources/main.swift || { rm -rf $@; exit 1; }
	cp Info.plist $@/Contents/Info.plist
	codesign --force --sign - --identifier $(LABEL) $@

run: build
	build/$(APP)/Contents/MacOS/scrollflip

install: build
	-launchctl bootout gui/$$(id -u)/$(LABEL) 2>/dev/null
	mkdir -p $(HOME)/Applications $(HOME)/Library/LaunchAgents
	rm -rf $(DEST) && cp -R build/$(APP) $(DEST)
	sed -e 's|__BIN__|$(BIN)|' launchagent.plist > $(AGENT)
	launchctl bootstrap gui/$$(id -u) $(AGENT)

uninstall:
	-launchctl bootout gui/$$(id -u)/$(LABEL)
	rm -rf $(AGENT) $(DEST)

restart:
	launchctl kickstart -k gui/$$(id -u)/$(LABEL)

logs:
	tail -f /tmp/scrollflip.log

clean:
	rm -rf build

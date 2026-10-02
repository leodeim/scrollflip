# ScrollFlip

Lightweight macOS app that reverses scroll direction for the mouse, the trackpad, or both.

## Install

Download the latest zip from [Releases](https://github.com/leodeim/scrollflip/releases).

Allow ScrollFlip in System Settings › Privacy & Security › Accessibility.

### From source

```sh
make install     # build, copy to ~/Applications
```

## Use

Click the menu-bar icon and tick **Reverse vertical** and/or **Reverse horizontal** under **Mouse** and **Trackpad**. A filled icon means it's active. Tick **Open at Login** to start it automatically.

## Other commands

```sh
make restart
make logs
make uninstall
```

## Footprint

- ~17 MB memory, mostly the AppKit baseline any menu-bar app pays
- ~0% CPU: it listens to scroll events only, with no timers or polling
- With all toggles off it receives no events at all
- ~270 KB universal binary (Apple Silicon + Intel), ~180 lines of Swift, no dependencies

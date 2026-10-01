# ScrollFlip

Lightweight macOS app that reverses scroll direction for the mouse, the trackpad, or both.

## Install

```sh
make install     # build, copy to ~/Applications, start at login
```

Then allow ScrollFlip in System Settings › Privacy & Security › Accessibility.

## Use

Click the menu-bar icon and tick **Reverse vertical** and/or **Reverse horizontal** under **Mouse** and **Trackpad**. A filled icon means it's active.

## Other commands

```sh
make restart     # start or restart it
make logs        # tail the log
make uninstall   # remove it
```

## Footprint

- ~17 MB memory, mostly the AppKit baseline any menu-bar app pays
- ~0% CPU: it listens to scroll events only, with no timers or polling
- With all toggles off it receives no events at all
- ~110 KB binary, ~160 lines of Swift, no dependencies

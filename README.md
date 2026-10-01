# ScrollFlip

macOS menu-bar app that reverses scroll direction for the mouse, the trackpad, or both.

## Install

```sh
make install     # build, copy to ~/Applications, start at login
```

Then allow ScrollFlip in System Settings › Privacy & Security › Accessibility.
After every rebuild, remove it from that list and add it again: the app is ad-hoc signed, so macOS treats each build as a new app.

## Use

Click the menu-bar icon and tick **Reverse mouse** and/or **Reverse trackpad**. A filled icon means it's active.

## Other commands

```sh
make restart     # start or restart it
make logs        # tail the log
make uninstall   # remove it
```

## Limitations

Mouse and trackpad are told apart by whether scrolling is discrete (wheel) or continuous, so a Magic Mouse counts as a trackpad.

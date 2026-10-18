# SmartClipBoard

Clipboard history in your MacBook's notch. Rest your pointer on the notch and it opens into a
Dynamic-Island-style panel with everything you copied recently. Click an item to copy it again, or
drag it anywhere.

## Features

- **Words**: each copied text becomes a chip that shows its first word. Hover a chip to read the full text.
- **Media**: copied photos, screenshots, GIFs and videos appear as thumbnails, each with a badge for its type.
- **Click to copy**, then press ⌘V anywhere. The app you're working in keeps focus.
- **Drag and drop** any item into Finder, the Desktop, Messages, Mail, Telegram, a browser or an editor.
- **Private**:
  - History is kept in memory only. It is never saved to disk and never sent over the network.
  - Passwords copied from password managers are skipped.
- **Light**: about 0% CPU and about 11 MB of memory when idle.
- **No accidental opens**: it opens only after your pointer rests on the notch for 0.7 s. While you
  wait, the notch swells slightly to show it's about to open. Move away and nothing happens.
- **Works without a notch too**: on other Macs and external displays, resting on the top centre of the screen opens it.

## Requirements

- macOS 14 Sonoma or later. Built and tested on macOS 26 Tahoe on a MacBook Air M2.
- Apple's free **Command Line Tools**. You don't need the full Xcode app.
  - If you don't have them, the installer tells you. Install them with `xcode-select --install`.

## Install

Open **Terminal** and run:

```bash
git clone https://github.com/M1ghtyyy/SmartClipBoard.git
cd SmartClipBoard
scripts/install.sh
```

The first build takes about a minute. The script then:

1. builds the app from source on your Mac,
2. copies it to `~/Applications/SmartClipBoard.app`,
3. turns on auto-start at login, and
4. starts it.

Rest your pointer on the notch for a moment and the island opens.

Keep the `SmartClipBoard` folder, because you'll use it to update or uninstall.

> **Why build from source?** Apps you build yourself aren't quarantined by macOS, so they open
> without "unidentified developer" warnings. You can also read every line of code that runs.

## Using it

| To | Do this |
|---|---|
| Open the island | Rest the pointer on the notch for 0.7 s. It swells slightly, then opens. |
| Copy an item again | Click it, then press ⌘V where you want it |
| Put an item somewhere directly | Drag it there |
| Read the full text of a chip | Hover the chip; the text appears in the header |
| Remove one item | Right-click it → **Remove** |
| Pause recording, clear the history, quit | Use the buttons at the top right of the island |

## Start, stop and auto-start

- **Start** it again after quitting: run `open ~/Applications/SmartClipBoard.app`, or type
  *SmartClipBoard* in Spotlight.
- **Quit**: click the power button in the island. If auto-start is on, it comes back at your next login.
- **Auto-start at login**: run these from the `SmartClipBoard` folder.

  ```bash
  scripts/autostart.sh status   # show whether it's on
  scripts/autostart.sh off      # stop starting at login (the app keeps running)
  scripts/autostart.sh on       # start at every login (restarts the app now)
  ```

Auto-start uses a per-user LaunchAgent, which is the standard macOS mechanism. It only affects
your user account and needs no admin password. If the app ever crashes, the LaunchAgent restarts
it.

The first time, macOS may show a **"Background Items Added"** notification. You'll then find the
entry under System Settings → General → Login Items.

## Update

To get the latest version and rebuild:

```bash
cd SmartClipBoard
git pull
scripts/install.sh
```

Your auto-start setting is kept. If the build fails after an update, rebuild from scratch with
`scripts/install.sh --clean`.

If you change the code yourself, run `scripts/install.sh` the same way to rebuild and restart.

## Uninstall

```bash
cd SmartClipBoard
scripts/uninstall.sh
```

Then delete the `SmartClipBoard` folder.

Already deleted the folder? These commands do the same thing:

```bash
launchctl bootout gui/$(id -u)/com.vladimirbelaev.smartclipboard 2>/dev/null
pkill -x SmartClipBoard
rm -f ~/Library/LaunchAgents/com.vladimirbelaev.smartclipboard.plist
rm -rf ~/Applications/SmartClipBoard.app "$(getconf DARWIN_USER_TEMP_DIR)SmartClipBoard"
```

## Scripts

| Command | What it does |
|---|---|
| `scripts/install.sh` | Build, install to `~/Applications`, start. Run it again to update. |
| `scripts/install.sh --no-autostart` | Same, but don't start at login. |
| `scripts/install.sh --clean` | Rebuild everything from scratch. |
| `scripts/autostart.sh on\|off\|status` | Change or check auto-start at login. |
| `scripts/build.sh` | Only build `build/SmartClipBoard.app`. Try it without installing: `open build/SmartClipBoard.app`. |
| `scripts/uninstall.sh` | Stop it and remove the app, the login item and temp files. |

## Permissions and privacy

- **No permissions needed**: no Accessibility, no Screen Recording, no network access.
- **Paste prompt**: macOS 15.4 and later may ask *"Allow SmartClipBoard to paste from other apps?"*.
  - Choose **Allow**.
  - The app is signed locally, so macOS may ask again after you rebuild it.
  - If you chose Don't Allow, the island shows a reminder. Turn access back on in System Settings →
    Privacy & Security → Paste from Other Apps.
- **Passwords**: copies marked as concealed or transient are never recorded. 1Password, Bitwarden,
  the Passwords app and Keychain Access all mark passwords this way.
- **Where history is kept**: text history stays in memory. Copied images (screenshots, "Copy
  Image") are kept in your private temp folder while the app runs and are deleted when it quits.

## Troubleshooting

| Problem | Fix |
|---|---|
| `xcrun: error: invalid active developer path` or "Command Line Tools are not installed" | Run `xcode-select --install`, then run `scripts/install.sh` again. |
| `package requires minimum Swift tools version 5.10` | Your Command Line Tools are too old. Update them in System Settings → General → Software Update. |
| Nothing happens when I hover the notch | Run `scripts/autostart.sh status`. If it says *not running*, start it with `open ~/Applications/SmartClipBoard.app`. |
| Copies don't show up | Make sure the header doesn't say *paused*. Then check System Settings → Privacy & Security → Paste from Other Apps. |
| I have two displays | The island stays on the built-in display, the one with the notch. With the lid closed it moves to the main display. |
| Only some copies appear | Copies from password managers are skipped on purpose. Files other than images and videos (PDFs, documents) are ignored. |

## How it works

SmartClipBoard is a small native Swift app (AppKit + SwiftUI) with no Dock icon and no
dependencies.

- Twice a second it checks a single counter that macOS increases on every copy. It reads the
  clipboard only when that counter changes.
- It sorts each copy into words or media and keeps it in memory.
- A borderless window sized exactly to the notch grows into the island when your pointer rests on it. The
  window never takes keyboard focus, so ⌘V always goes to the app you were using.

For the details, including CPU and memory measurements and every file the app touches, see
[docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).

## Building in Xcode (optional)

You can open the project in Xcode with `open Package.swift` to get SwiftUI previews and the
Instruments profiler. Run the **SmartClipBoard** scheme.

Quit the installed copy first, so you don't end up with two islands.

## License

[MIT](LICENSE)

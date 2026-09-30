# QDVC Nice Mail for macOS

Write emails faster by keeping your most-used building blocks one click away:
a searchable **emoji** picker with favourites and skin tones, a library of
reusable **phrases**, an assembled plaintext mail **signature**, and a
**Note to Self** writer that saves self-addressed `.eml` files. A native
SwiftUI app for macOS 14 (Sonoma) and later.

Your data is a plain folder of CSV and text files (the format is documented in
[docs/FILE_FORMAT.md](docs/FILE_FORMAT.md)), shared with the Python/GTK
edition of [QDVC Nice Mail](https://github.com/qdvc-apps/qdvc-nice-mail), so
you can use the same workspace on Linux and on a Mac. You don't need that
edition to use this one.

## What it does

The window has four tabs, switched with the segmented control in the toolbar
(⌘1–⌘4), as in Activity Monitor. Each tab brings its own toolbar buttons.

- **Emoji** — a table of emoji (symbol, name, and your optional user label).
  **Show** switches between your *Favourites* (in your order) and *All Emoji*.
  Search (⌘F) matches the name, id or your label. Double-click a row, press
  ⌘C, or use **Copy** to copy the emoji, with your skin tone applied
  (Settings, ⌘,). Right-click to add or remove a favourite, set a user label,
  or move it up or down (also in the **Emoji** menu, ⌥⌘↑ / ⌥⌘↓). Emoji that
  aren't in the list, such as many multi-part emoji like ❤️‍🩹, can be pasted in
  with **Add Custom**; they are saved to your favourites and also listed under
  *All Emoji*.
- **Phrases** — your phrases in alphabetical order, with search, **Add** (⌘N),
  **Edit** and **Delete** (⌫, with confirmation). Double-click, ⌘C or **Copy**
  copies the selected phrase.
- **Signature** — the assembled plaintext signature (see below). Pick a
  **profile**, toggle the **Disclaimer**, or turn on **Ref Only** to keep just
  the m-dash and the message ref line. **New Ref** (⇧⌘R) makes a fresh message
  ref. ⌘C copies the selection, or the whole signature when nothing is
  selected; **Copy** always copies the whole signature. Your profile,
  Disclaimer and Ref Only choices are remembered.
- **Note to Self** — a **From / To** address (remembered), a **subject** and a
  plain-text **body**. A green callout shows the message ref the note will
  carry. **Send** (⌘S) saves a self-addressed `.eml` file (From and To are the
  same address, dated now) whose body is your text followed by the m-dash and
  message-ref trailer; open it in Mail to send it. The default file name is
  `yyyy-mm-dd-message-ref-<ref>.eml`. After saving, the subject and body are
  cleared and a new message ref is made. The note's ref is independent of the
  Signature tab's.

**View → Refresh** (⌘R) re-reads the workspace from disk, and on the Signature
and Note to Self tabs also makes a new message ref. **Edit → Copy from Current
Tab** (⇧⌘C) copies the selected emoji or phrase, or the whole signature,
wherever the keyboard focus is.

### Signature format

```
Kind regards,

John Smith


—

John Smith
Specialist and Superhero
Data by day, defeating villains by night

Disclaimer: a disclaimer text goes here

Message ref. YyM4mRnjHQ
```

Everything before the m-dash comes from `mailsigs/signoff.txt`, followed by an
extra blank line; the block after it is the selected profile; the disclaimer
line appears only when the toggle is on. The 10-character message ref is drawn
from an unambiguous alphabet
(`346789ABCDEFGHJKLMNPQRTUVWXYabcdefghijkmnpqrtwxyz`).

## Requirements

- macOS 14 Sonoma or later.
- Xcode 16 or later (free from the Mac App Store). The Command Line Tools
  alone can build and run the app, but `swift test` needs full Xcode.
- No paid Apple Developer account.

## Build and run

From the repository root:

```sh
swift run                                # build and launch (debug)
swift run QDVCNiceMail sample-workspace  # …opening the sample workspace
swift test                               # run the unit and parity tests
scripts/build-app.sh                     # build "build/QDVC Nice Mail.app" (release)
scripts/build-app.sh --install           # …and copy it to ~/Applications
```

Or open the repository folder in Xcode (File → Open…, choose the folder that
contains `Package.swift`), pick the **QDVCNiceMail** scheme and press ⌘R.
Xcode may ask for a team: choose **None** / **Sign to Run Locally**.

A ready-made `sample-workspace/` is included to try the app straight away.
Opening any other folder, even an empty one, creates the missing files with
defaults.

## Signing without a paid account

`scripts/build-app.sh` signs the app **ad hoc** (`codesign --sign -`). That is
all macOS needs to run an app on the Mac that built it — no account, no
certificate, no notarisation.

A paid Developer ID is only needed to *distribute* the app so that it opens on
other Macs without a warning. If you give the ad-hoc-signed app to someone
else, macOS will block the first launch; they can allow it once in
**System Settings → Privacy & Security → Open Anyway**, or remove the
quarantine flag in Terminal:

```sh
xattr -dr com.apple.quarantine "/Applications/QDVC Nice Mail.app"
```

Because an ad-hoc signature changes with every build, macOS may ask again for
permission to access folders such as Documents, Desktop or iCloud Drive after
you rebuild. That is expected.

## Where things are stored

- Your emoji favourites, phrases and signature files: only in the workspace
  folder you open, in the format described in
  [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md). Every change is written to disk
  straight away.
- Preferences and remembered choices (skin tone, signature font, profile,
  toggles, the Note to Self address, recent workspaces): the standard macOS
  defaults domain (`defaults read org.qdvc.NiceMail`).
- Saved notes: wherever you choose in the Save panel.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘1–⌘4 | Emoji, Phrases, Signature, Note to Self |
| ⌘O | Open workspace |
| ⇧⌘W | Close workspace |
| ⌘F | Search (Emoji and Phrases tabs) |
| ⌘C | Copy the selected emoji or phrase, or the signature |
| ⇧⌘C | Copy from the current tab, wherever the focus is |
| ⌘N | New phrase |
| ⌘D | Add to / remove from favourites |
| ⌘L | Set a favourite's user label |
| ⌥⌘↑ / ⌥⌘↓ | Move a favourite up / down |
| ⌘R | Refresh (and a new message ref on Signature and Note to Self) |
| ⇧⌘R | New message ref |
| ⌘S | Send the note to self (save the `.eml`) |
| ⌘, | Settings |
| Double-click a row | Copy it |

## Documentation

- **[docs/FILE_FORMAT.md](docs/FILE_FORMAT.md)** — the workspace format: folder
  layout, the CSV files, ids, signature and note formats.
- **[docs/MAINTENANCE.md](docs/MAINTENANCE.md)** — architecture, modules,
  behaviour to preserve, deliberate differences from the Python edition,
  tests, and the roadmap.

## License

No license has been chosen yet. Add a `LICENSE` file before publishing.

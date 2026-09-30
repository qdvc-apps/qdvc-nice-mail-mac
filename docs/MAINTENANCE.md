# QDVC Nice Mail for macOS — Maintenance Guide

This guide covers the architecture and upkeep of QDVC Nice Mail for macOS.
The on-disk workspace format is specified in [FILE_FORMAT.md](FILE_FORMAT.md);
read that first.

The app began as a port of the Python/GTK edition of QDVC Nice Mail
(<https://github.com/qdvc-apps/qdvc-nice-mail>), following the approach of the
QDVC Bibliotheca macOS port, and shares its file format, so the two can open
the same workspace. This repository does not depend on that codebase: it
builds, runs and tests on its own. The Python edition is mentioned below only
as the origin of some modules, and as the optional source of the parity
fixtures (§5).

---

## 1. Layout

```
(repository root)
  Package.swift                 SwiftPM manifest (tools 5.10, macOS 14+)
  Sources/
    NiceMailCore/               pure model layer — Foundation only
    QDVCNiceMail/               SwiftUI/AppKit front-end (the executable)
  Tests/NiceMailCoreTests/      XCTest: parity + core tests
    Fixtures/parity.json        committed reference outputs (see §5)
  tools/make_fixtures.py        optional: regenerates parity.json (see §5)
  tools/make_icon.py            regenerates the app icon (see §1.1)
  Resources/Info.plist          bundle metadata used by scripts/build-app.sh
  Resources/AppIcon.svg         the icon's vector master (generated)
  Resources/AppIcon.icns        the icon, all sizes (generated)
  scripts/build-app.sh          builds and ad-hoc signs the .app
  sample-workspace/             a small workspace to try the app with
  docs/FILE_FORMAT.md           the workspace format specification
  docs/HIG.md                   window layout decisions and their HIG precedents
```

There is deliberately no `.xcodeproj`: Xcode opens `Package.swift` directly,
and a hand-maintained project file would be one more thing to keep in sync.
The `.app` bundle is assembled by `scripts/build-app.sh` from the SwiftPM
release binary, `Resources/Info.plist` and `Resources/AppIcon.icns`.

### 1.1 App icon

The icon is a frosted-glass envelope sealed with a smiling face, in the
macOS 26 Liquid Glass style, on a pale "Butter" tile (cream `#FFF9DC` to
butter yellow `#F2CB5A`) chosen to complement the yellow smiley and to look
unlike Mail.app. The smiley is drawn from simple shapes by the script, not
taken from any emoji font. It is built the same way as the icon of QDVC
Bibliotheca for macOS, so the two apps look like a family.
`tools/make_icon.py` draws it as SVG and writes `Resources/AppIcon.svg` and
`Resources/AppIcon.icns`; both are committed, so building needs nothing extra.
To change the design or palette, edit the constants at the top of the script
and run `python3 tools/make_icon.py` (needs `rsvg-convert`:
`brew install librsvg`; `--preview` also writes `build/icon-preview.png`).
Every size in the `.icns` is rendered from the vector, not scaled down, so
small sizes stay sharp.

The geometry follows Apple's macOS icon template: an 824 × 824 tile centred
on a 1024 × 1024 canvas (100 px transparent margin), with a 185.4 px corner,
and a black drop shadow (28 px blur, 12 px down, 50 %). The corner uses
Apple's *continuous-curvature* rounded rectangle: the curve UIKit draws, as
reverse-engineered and published by PaintCode. It is not a superellipse; a
whole-shape superellipse looks slightly too round, because it starts curving
before Apple's corner does. macOS applies no mask to Mac app icons, so the
shape, margin and shadow must be baked into the artwork, as the script does.

The pale tile has little contrast with a light desktop, so the envelope and
smiley carry a shadow tinted with the deep butter tone, and the smiley has a
white ring. Keep both if you change the palette, and check the 32 px size.

If Finder or the Dock keeps showing an old icon after a rebuild, that's the
system icon cache; re-copying the app (for example
`scripts/build-app.sh --install`) usually refreshes it.

The package has no dependencies, so there is no `Package.resolved`. If one is
ever added, commit the `Package.resolved` that SwiftPM creates, so every
checkout builds the same code.

`Package.swift` declares the app target only when evaluated on macOS. The
core and its tests therefore also build with a Linux Swift toolchain, which
is how the port was developed and is handy for CI.

The package uses Swift language mode 5 (tools version 5.10), so strict
concurrency checking is off. The UI types are `@MainActor`; `Workspace` and
`EmojiCatalogue` are marked `@unchecked Sendable` because they are only ever
used from the main actor.

---

## 2. Modules

`NiceMailCore` (no AppKit or SwiftUI; everything here is unit-tested):

| File | Responsibility | Origin in the Python edition |
| --- | --- | --- |
| `TextSupport.swift` | Python-compatible string helpers (`strip`, `splitlines`, universal newlines, code-point order), atomic file IO | — |
| `Naming.swift` | emoji ids, custom-glyph ids, message refs | `naming.py` |
| `Emoji.swift` | `SkinTone`, `Emoji`, `EmojiCatalogue` (range scan, custom glyphs, search) | `emoji.py` |
| `Models.swift` | `Phrase`, `Profile` | `models.py` |
| `Signature.swift` | signature assembly | `mailsig.py` |
| `Note.swift` | Note to Self body, `.eml` builder (body encoding, headers, date), file name | `note.py` + Python's `email` package |
| `CSV.swift` | reader and writer matching Python's `csv` (excel dialect) | Python's `csv` |
| `Workspace.swift` | scaffold, scan, favourites, phrases, profiles, validation | `workspace.py` |

`QDVCNiceMail` (the app):

| File | Responsibility |
| --- | --- |
| `NiceMailApp.swift` | `@main` app, single `Window` scene, app delegate (activation, ⌘F monitor) |
| `Commands.swift` | menu-bar commands and shortcuts, including the Emoji menu |
| `ContentView.swift` | tab switching (toolbar segmented control), the one sheet host, `TextPromptSheet`, welcome screen |
| `ToolbarControls.swift` | shared controls: icon-only Copy and New Ref toolbar buttons, the `ListControlBar` (+ − under a list) and the `OptionBar` |
| `EmojiTabView.swift` | the Emoji `Table`, its list bar, toolbar and context menu (`EmojiMenuItems`) |
| `PhrasesTabView.swift` | the Phrases `Table`, list bar, toolbar, context menu, delete confirmation |
| `SignatureTabView.swift` | the signature preview, its option bar and toolbar |
| `NoteTabView.swift` | the Note to Self form and green callout |
| `TextViews.swift` | `NSTextView` wrappers: `SignaturePreview` (with `CopyAllTextView`) and `PlainTextEditor` |
| `AppModel.swift` | all window state and actions |
| `Prefs.swift`, `SettingsView.swift` | preferences and the Settings window |
| `Platform.swift` | pasteboard, Finder, toolbar search-field focus |

`AppModel` is the single `@Observable` object behind the window. Every action
that changes the workspace goes through it, then calls the matching
`refreshEmojiRows()`, `refreshPhraseRows()` or `refreshSignature()`, so the
table rows and preview stay consistent. Rows are value
snapshots (`EmojiRow`, `Phrase`), which keeps `Table` diffing cheap.

Each tab view adds its own few toolbar items (and, on Emoji and Phrases, its
own `.searchable` field), so the toolbar changes with the tab, like the Python
edition's per-tab toolbar. The centred segmented control belongs to
`ContentView`. The layout rules (what goes in the toolbar, in the list bars
and in the option bar; icon-only buttons; no title or status text) are in
[HIG.md](HIG.md); follow them when adding controls.

---

## 3. Behaviour that must be preserved

- **File formats.** Everything in [FILE_FORMAT.md](FILE_FORMAT.md). Files
  written by this app and by the Python edition are byte-identical (CSV
  quoting and CRLF line endings, row order, the `_2` suffixes of phrase ids);
  the parity tests check this after every kind of change. If you change the
  format, update FILE_FORMAT.md in the same commit.
- **Emoji ids.** The catalogue must keep scanning the same ranges in the same
  order, naming code points from Unicode data and resolving collisions with
  `_2`, `_3`…; otherwise existing favourites stop resolving. Don't curate or
  reorder the list in the core; filter in the UI if needed.
- **Writes happen immediately.** Every favourite or phrase change writes its
  file at once (atomically). There is no unsaved state and nothing to flush on
  quit.
- **Message refs.** The Signature and Note to Self refs are independent. On
  those tabs, the New Ref button is View → Refresh (⌘R), which re-reads the
  workspace and makes a new ref; Send makes a new note ref after saving. Refs come from `SystemRandomNumberGenerator`
  (cryptographically secure on macOS).
- **Signature copy.** ⌘C on the Signature tab copies the whole signature when
  nothing is selected (`CopyAllTextView`), so the preview must stay a
  `CopyAllTextView`, and it takes focus when the tab opens.
- **Copy feedback.** Every copy of an emoji, phrase or the signature goes
  through `AppModel.noteCopied()`, which shows the checkmark on the Copy
  toolbar button (HIG.md §4). New copy paths must call it too.
- **⌘F** is caught by a local key monitor in `AppDelegate` only on the Emoji
  and Phrases tabs (and not while a sheet is open), and moves focus to the
  toolbar search field. Elsewhere it passes through, so the note body and the
  signature preview keep the standard Find bar.
- **Nothing may demand a large minimum size.** Every `NSViewRepresentable`
  implements `sizeThatFits(_:nsView:context:)` and returns the proposed size.
  Otherwise SwiftUI falls back to the AppKit fitting size, which for scroll
  views can be huge and pushes the window layout out of shape. (Learned the
  hard way in the Bibliotheca port.)
- **One sheet at a time.** Every sheet is a case of `ActiveSheet`, presented
  by a single `.sheet(item: $model.activeSheet)` in `ContentView`. Sheets only
  collect input; the `AppModel` method that applies the change also closes
  the sheet. A method that can fail with a message the user should see (Add
  Custom Emoji) returns it instead, and the sheet stays open and shows it.
- **Return triggers a sheet's default button even inside a text field**
  (standard AppKit behaviour).

---

## 4. Deliberate differences from the Python edition

- **Hidden files in `mailsigs/profiles/`** (`.DS_Store`, `._` AppleDouble
  files) are ignored: they neither appear as profiles nor stop the default
  profile being created in an otherwise empty folder.
- **A UTF-8 byte-order mark** at the start of a CSV file is tolerated; the
  Python edition would not find the first column.
- **Invalid UTF-8** in a file is read with replacement characters instead of
  raising an error.
- **Non-ASCII headers in `.eml` files** are RFC 2047 encoded words, as in
  Python, but may be split into words differently (for example, ASCII words
  between accented ones stay plain here). They decode to the same text, and
  plain ASCII headers are byte-identical. Bodies are always byte-identical.
- **Preferences** live in `UserDefaults` (keys in `Prefs.Key`), not in the
  Python YAML config. The toolbar-style and GTK-backend preferences have no
  Mac equivalent. The signature font is a family and size instead of a Pango
  font description.
- **Window layout and menus** follow macOS conventions (see
  [HIG.md](HIG.md)): tabs in a centred segmented control (⌘1–⌘4 instead of
  Alt+1–4), icon-only toolbar buttons, list buttons in a bar under each list,
  the Signature options as checkboxes above the preview, no status bar (a
  checkmark on the Copy button confirms copies), New Ref on ⌘R (Refresh)
  instead of F5, and an Emoji menu for the favourite actions.

Two quirks are reproduced for parity rather than fixed. They are worth fixing
in both editions together, then regenerating the fixture: a phrase whose first
32 characters contain no letters or digits gets the id `emoji`, because the
phrase-id rule reuses the emoji-id helper and its fallback; and the Emoji
catalogue includes non-emoji symbols from the scanned ranges (arrows,
alchemical symbols), because the Python edition names every code point there.

### 4.1 The Windows edition

The Windows edition (<https://github.com/qdvc-apps/qdvc-nice-mail-windows>)
was built from the Python edition's README rather than its code, and differs
from it in ways this edition does not copy: one blank line (not two) before
the signature's m-dash; no `Disclaimer: ` prefix (its sample `disclaimer.txt`
contains the prefix instead); one blank line (not two) between a note's text
and its trailer; numeric phrase ids; and a curated list of about 1,400 emoji
instead of every named code point in the scanned ranges. The workspace files
remain readable by all three editions, but the same workspace gives slightly
different signatures on Windows.

---

## 5. Tests

`swift test` runs two suites:

- **ParityTests** feed the inputs in `Fixtures/parity.json` through the Swift
  core and compare with the reference outputs recorded there: emoji ids,
  custom glyph ids and names, skin tones, the whole catalogue (ids, glyphs,
  names, order), search, signatures, note bodies, `.eml` files (39 cases,
  bodies byte-identical), file names, the scaffold, and three workspace
  scenarios that replay a series of favourite and phrase changes and compare
  every file byte for byte afterwards.
- **CoreTests** cover the deliberate differences in §4 and the helpers: CSV
  edge cases, hidden profile files, the byte-order mark, the sample
  workspace, header encoding and folding, date offsets and quoted-printable
  escapes.

`parity.json` is committed, so the tests need nothing outside this
repository. The reference outputs in it were produced by running the Python
edition's code (Python 3.12, Unicode 15.0). To re-check against a newer
Python edition (optional), point the generator at a checkout of it, then
rerun the tests:

```sh
python3 tools/make_fixtures.py --python-repo /path/to/qdvc-nice-mail
swift test
```

To add a parity case, add an input to the lists in `tools/make_fixtures.py`;
the Swift side iterates over whatever is there. If you decide to diverge from
the Python edition deliberately, move that case into `CoreTests` with the
expected value written out, and record the difference in §4.

The catalogue test allows a newer macOS to know more characters than the
fixture (they may appear between existing entries), but every fixture entry
must exist with the same id, glyph and name, in the same relative order.

The core and its tests also run on Linux with Swift 5.10 or later
(`swift test` there skips the app target).

---

## 6. Roadmap

1. ~~App icon~~ — done (§1.1).
2. **Continuous integration** — a GitHub Actions workflow that runs
   `swift test` and `scripts/build-app.sh` on a macOS runner and uploads the
   bundle; the core tests could also run on a cheaper Linux runner.
3. **Open in Mail after Send** — offer to open the saved `.eml` in Mail (or
   reveal it in Finder) straight after saving, for example as an option in
   the Save panel or a small sheet; there is no status bar to put it in.
4. **Drag and drop out** — drag an emoji or phrase from its table into another
   app (`Transferable` rows).
5. **Live refresh** with FSEvents, so edits made in a text editor or by a sync
   client appear without ⌘R.
6. **Emoji inspector** — a right-hand details panel for the selected emoji
   (name, code points, label, favourite); see HIG.md §3.
7. **Menu bar extra** — a small favourites and phrases picker available from
   the menu bar while writing in another app.

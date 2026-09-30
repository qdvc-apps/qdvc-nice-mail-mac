# Human Interface Guidelines notes

This document records how QDVC Nice Mail for macOS lays out its window and
why, with reference to Apple's
[Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines)
(HIG) and to Apple apps that set the precedent. Read it before adding a
toolbar item, a button or a new tab, so the app stays consistent.

The precedents below describe these apps as of macOS 14–15. Apple sometimes
rearranges its own apps, so check the current version when it matters.

---

## 1. Navigation: four modes, one segmented control

The four tabs (Emoji, Phrases, Signature, Note to Self) are fixed modes of one
window, not a list of things to browse. They are switched with a segmented
control centred in the toolbar, mirrored in the View menu with ⌘1–⌘4.

Precedents: **Activity Monitor** (CPU, Memory, Energy, Disk, Network),
**Clock** (World Clock, Alarms, Stopwatch, Timers), **Calendar** (Day, Week,
Month, Year, ⌘1–⌘4) and **Finder**'s view modes (⌘1–⌘4). The tab control also
matches what people know from the Linux and Windows editions.

Considered and rejected:

- **A sidebar.** Apple uses sidebars for master–detail browsing of many,
  often growing, items (Mail, Notes, Music, Finder locations), not for a
  fixed handful of modes.
- **Settings-style toolbar tabs** (a row of large icons with small labels, as
  in Mail → Settings). The HIG describes this style for settings windows;
  on a main window it reads as a preferences window, leaves no toolbar room
  for commands, and implies a fixed-size, resizing-per-pane window.
- **Window tabs** (Terminal, Safari) are for several documents of one kind.
- **A ribbon.** Mac-native apps avoid it; it appears mainly in cross-platform
  software. Apple's own equivalent (Keynote, Pages, Numbers) is a short
  toolbar plus a Format inspector.

## 2. The toolbar

Each tab's toolbar holds at most: one picker at the leading edge, the centred
tab control, and one or two **icon-only** actions plus search at the trailing
edge. Everything else lives in the content (§3). This keeps the toolbar
steady from tab to tab, as in Activity Monitor, and lets the window work at
about half the width of a laptop screen. The window's minimum size is
640 × 420 pt.

| Tab | Leading | Trailing |
| --- | --- | --- |
| Emoji | Show (Favourites / All Emoji) | Copy, search |
| Phrases | — | Copy, search |
| Signature | Profile | New Ref, Copy |
| Note to Self | — | New Ref, Send |

- **No window title or subtitle in the toolbar**, as in Calendar
  (`.windowToolbarStyle(.unified(showsTitle: false))`). The title (the
  workspace folder's name) is still set, so it names the window in the Window
  menu, Mission Control and VoiceOver. There is no status text; see §4 for
  copy feedback. Errors are shown in alerts.
- **Icon-only buttons**, the HIG's preference for toolbars. Every button
  keeps its text label (used by VoiceOver and in the toolbar's overflow menu)
  and a tooltip naming the action and its shortcut, and every action is also
  in the menu bar.
- The search field collapses to a magnifying-glass button when space is
  short (standard macOS behaviour), and ⌘F focuses it on the Emoji and
  Phrases tabs.
- The toolbar is not user-customisable: the per-tab items make customisation
  confusing, and with so few items there is little to gain.

### Symbols

| Action | SF Symbol | Notes |
| --- | --- | --- |
| Copy | `doc.on.doc` | Becomes `checkmark` for 1.5 s after a copy (§4). |
| New Ref | `arrow.clockwise` | A new message ref is a refresh of the tab: the button runs View → Refresh (⌘R), which on the Signature and Note to Self tabs re-reads the workspace and makes a new ref. |
| Send | `paperplane` | Matches the button's name. Mail uses an up arrow for Send, so there is no clash; the tooltip explains that it saves an `.eml` file. |
| Add | `plus` | List bar (§3). |
| Delete | `minus` | List bar; asks for confirmation. |
| Edit | `pencil` | List bar. |
| Move Up / Down | `arrow.up` / `arrow.down` | List bar; favourites only. |

## 3. Controls in the content

**List bars.** Actions that manage a list's rows sit in a small bar attached
to the bottom edge of the list, with the buttons at the left: Apple's
traditional **+ −** pattern, as in System Settings, Mail → Settings → Accounts
and Keychain Access (`ListControlBar` in `ToolbarControls.swift`).

- Emoji: **+** (Add Custom Emoji…), then **↑ ↓** (Move Up / Down).
- Phrases: **+** (Add), **−** (Delete), then **✎** (Edit).

A floating, centred Liquid Glass bar (as in QuickTime Player or the
Screenshot toolbar) was considered and rejected: it is a media and canvas
idiom, it covers the list's last rows, and it would only look right on
macOS 26.

**Option bar.** Options that change what a tab shows sit in a slim,
left-aligned bar between the toolbar and the content, as in Preview's Markup
toolbar (`OptionBar`). The Signature tab's **Include disclaimer** and
**Ref only** are checkboxes there (checkboxes, not toggle buttons, being the
Mac control for independent options). Include disclaimer is disabled while
Ref only is on. Pickers that choose *which* content is shown (Emoji's Show,
Signature's Profile) stay in the toolbar, consistently on both tabs.

**Inspector.** A right-hand inspector (as in Keynote or Xcode) is for viewing
and editing properties of the selection, not for commands, and it costs
width. None is used now; an emoji details inspector (name, code points,
label, favourite) would be the natural first one.

## 4. Feedback

The app's main job is copying, so copying needs confirmation, but not a
status line. After any copy of an emoji, a phrase or the whole signature
(toolbar button, ⌘C, ⇧⌘C, double-click or a context menu) the toolbar's Copy
button shows a checkmark for 1.5 seconds (`AppModel.justCopied`). Copying
selected text in a text view is left to the standard behaviour. Other changes are visible in place (a new row is
selected, a moved favourite stays selected, a sent note clears the form and
shows its new ref), so they need no message.

## 5. Keyboard and menus

Every toolbar, list-bar and context-menu action has a menu-bar command, and
the frequent ones have shortcuts. The menu bar, not the toolbar, is the place
for discoverability; if you add a control, add its command too.

| Shortcut | Action |
| --- | --- |
| ⌘1–⌘4 | Switch tab |
| ⌘C | Copy the focused item (a row, selected text, or the whole signature) |
| ⇧⌘C | Copy from the current tab, wherever the focus is |
| ⌘F | Search (Emoji and Phrases) |
| ⌘R | Refresh; a new message ref on Signature and Note to Self |
| ⌘N | New phrase |
| ⌫ | Delete the selected phrase |
| ⌘D, ⌘L | Add to / remove from favourites; set a favourite's label |
| ⌥⌘↑ / ⌥⌘↓ | Move a favourite up / down |
| ⌘S | Send the note to self |

Double-clicking a row copies it, as in the other editions.

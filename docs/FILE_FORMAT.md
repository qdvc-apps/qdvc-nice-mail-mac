# Workspace file format

A QDVC Nice Mail workspace is an ordinary folder of UTF-8 text files. The
files are the database: there is no index or cache, every change is written
straight away, and you can edit any file in a text editor (use View → Refresh,
⌘R, to pick up changes). The format is the one used by the Python/GTK edition
of [QDVC Nice Mail](https://github.com/qdvc-apps/qdvc-nice-mail); this edition
writes byte-identical files, which the parity tests check (see
[MAINTENANCE.md](MAINTENANCE.md) §5).

## Layout

```
<workspace>/
    favourite_emoji.csv        id,label,char
    phrases.csv                id,text
    mailsigs/
        signoff.txt            everything before the m-dash
        disclaimer.txt         the disclaimer text
        profiles/
            <name>.txt         one signature profile per file
```

Opening a folder creates whatever is missing:

| File | Default content |
| --- | --- |
| `favourite_emoji.csv` | one favourite, 😊 (`smiling_face_with_smiling_eyes`) |
| `phrases.csv` | `thanks` — "Thanks very much for your help."; `follow_up` — "Just following up on my previous email." |
| `mailsigs/signoff.txt` | `Kind regards,`, a blank line, `John Smith` |
| `mailsigs/disclaimer.txt` | `a disclaimer text goes here` |
| `mailsigs/profiles/default.txt` | `John Smith`, `Specialist and Superhero`, `Data by day, defeating villains by night` — only when the profiles folder has no files |

Existing files are never overwritten.

## CSV files

Both CSV files use the dialect of Python's `csv` module (and of Excel): comma
separators; a header row; fields containing a comma, a double quote or a line
break are wrapped in double quotes, with inner quotes doubled; rows end with
CRLF (`\r\n`) when written. Reading accepts LF, CR or CRLF line endings, skips
blank lines, trims spaces around values, and ignores rows with an empty `id`.
Columns are found by header name, so their order doesn't matter and missing
columns read as empty. A UTF-8 byte-order mark before the header is tolerated
by this edition (the Python edition would not find the first column).

### favourite_emoji.csv

```
id,label,char
smiling_face_with_smiling_eyes,,
waving_hand_sign,"hello, there",
custom_2764_fe0f_200d_1fa79,mended,❤️‍🩹
```

- `id` — the emoji's id (below). Row order is the order of the Favourites list;
  Move Up/Down rewrites it. A repeated id keeps only its first row.
- `label` — the optional user label, shown in the User Label column and matched
  by search.
- `char` — the glyph, for custom (pasted) emoji only; blank for emoji from the
  catalogue.

An older single-column file (`id` only) is read as favourites without labels,
and gains the other columns the next time it is written. Favourite ids that
match neither the catalogue nor a stored glyph are kept in the file but not
shown.

### phrases.csv

```
id,text
thanks,Thanks very much for your help.
follow_up,Just following up on my previous email.
```

- `id` — a stable id, made when the phrase is added: the first 32 characters of
  the text in snake_case (the emoji-id rule below), with `_2`, `_3`… added if
  that id is taken. Editing a phrase keeps its id.
- `text` — the phrase. It may contain line breaks (the field is then quoted).

The file keeps phrases in the order they were added; the app lists them
alphabetically (case-insensitive).

## Emoji ids

A catalogue emoji's id is its Unicode character name in snake_case: lower-case,
every run of characters other than `a–z` and `0–9` replaced by one underscore,
and underscores trimmed from the ends (`WAVING HAND SIGN` → `waving_hand_sign`).
An empty result becomes `emoji`.

The catalogue is every named code point in these ranges, scanned in this
order:

1. U+1F300–U+1FAFF (pictographs, emoticons, transport, supplemental symbols)
2. U+2600–U+27BF (miscellaneous symbols and dingbats)
3. U+2190–U+21FF (arrows)
4. U+2B00–U+2BFF (miscellaneous symbols and arrows)

When two names give the same id, the later one gets `_2`, then `_3`, and so
on, in scan order (for example the alchemical symbols). A custom emoji's id is
`custom_` followed by its code points in lower-case hexadecimal, joined with
underscores: ❤️‍🩹 is `custom_2764_fe0f_200d_1fa79`.

Names come from each system's Unicode data. A newer system may add characters
to the catalogue; ids of existing characters never change, so favourites stay
valid across editions and system versions.

## Signature files

Text files are read as UTF-8 with any line endings (they are normalised to LF).

- `mailsigs/signoff.txt` — everything before the m-dash, for example
  `Kind regards,` and your name. Trailing line breaks are ignored.
- `mailsigs/disclaimer.txt` — the disclaimer text. Leading and trailing white
  space is trimmed, and the signature adds the `Disclaimer: ` prefix, so don't
  put it in the file.
- `mailsigs/profiles/<name>.txt` — one profile per file, listed by file name
  (sorted by code point, so capitalised names come first). Its lines, minus
  trailing blank lines, form the block after the m-dash. Only files ending in
  lower-case `.txt` are profiles; this edition also skips hidden files, such
  as `.DS_Store` and `._` files.

### Assembled signature

```
<signoff>
(blank)
(blank)
—
(blank)
<profile block>
(blank)
Disclaimer: <disclaimer>
(blank)
Message ref. <ref>
```

Parts are separated by one blank line, with an extra blank line before the
m-dash (U+2014). An empty profile, or a disabled or empty disclaimer, is left
out along with its separator; with an empty signoff the signature starts with
the blank line before the m-dash. The text ends with a line break.
In Ref Only mode the signature is just:

```
—
(blank)
Message ref. <ref>
```

A message ref is 10 characters drawn at random, using the system's secure
random number generator, from `346789ABCDEFGHJKLMNPQRTUVWXYabcdefghijkmnpqrtwxyz`,
which leaves out look-alike characters such as 0/O, 1/l/I, 2/Z and 5/S.

## Note to Self files

Send saves an RFC 5322 message with LF line endings, which Mail and other
clients open directly:

```
From: me@example.com
To: me@example.com
Subject: Hello
Date: Wed, 30 Sep 2026 10:00:00 +0100
Content-Type: text/plain; charset="utf-8"
Content-Transfer-Encoding: 8bit
MIME-Version: 1.0

Body text


—

Message ref. ABCDEFGHJK
```

- From and To are the same address, as typed (a display name such as
  `Jane Doe <jane@example.com>` is allowed). An empty address gives empty
  headers.
- The body is your text without trailing line breaks, two blank lines, the
  m-dash, a blank line and the message-ref line.
- The Content-Transfer-Encoding follows the rules of Python's `email` package:
  `7bit` for ASCII text, `8bit` for other text whose lines are all at most 78
  bytes long, and otherwise `quoted-printable` or `base64`, whichever is
  shorter for the first ten lines.
- Non-ASCII header text is sent as RFC 2047 encoded words; long headers are
  folded at 78 characters.

The default file name is `yyyy-mm-dd-message-ref-<ref>.eml`, dated today.

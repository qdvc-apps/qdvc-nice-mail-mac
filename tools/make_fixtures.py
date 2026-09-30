#!/usr/bin/env python3
"""Regenerate the parity fixtures from the Python/GTK edition of the app.

This is an optional maintenance tool. The Swift tests read the committed
Tests/NiceMailCoreTests/Fixtures/parity.json and need nothing else; run this
script only when you want to re-check the Swift port against a newer version
of the Python reference implementation.

It runs the Python edition's pure core (the `qdvc` package) over a set of
sample inputs and workspace scenarios, and writes the results to parity.json.

Usage:

    python3 tools/make_fixtures.py --python-repo /path/to/qdvc-nice-mail

The path is a checkout of https://github.com/qdvc-apps/qdvc-nice-mail (the
folder that contains the `qdvc` package). The QDVC_PYTHON_REPO environment
variable can be used instead of the option. Needs only the standard library.
"""

import argparse
import base64
import json
import os
import sys
import tempfile
import unicodedata
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
OUT = HERE / "Tests" / "NiceMailCoreTests" / "Fixtures" / "parity.json"

def _import_reference(python_repo: Path):
    if not (python_repo / "qdvc" / "__init__.py").is_file():
        sys.exit(f"error: {python_repo} does not contain the qdvc package")
    sys.path.insert(0, str(python_repo))
    global emoji_mod, naming, mailsig, note, models, Workspace
    from qdvc import emoji as emoji_mod  # noqa: F401
    from qdvc import mailsig, models, naming, note  # noqa: F401
    from qdvc.workspace import Workspace  # noqa: F401


EMOJI_ID_INPUTS = [
    "GRINNING FACE WITH SMILING EYES",
    "  WAVING HAND SIGN ",
    "EMOJI MODIFIER FITZPATRICK TYPE-1-2",
    "T-REX",
    "--weird__name!!",
    "",
    "!!!",
    "Thanks very much for your help.",
    "Réunion de l’équipe",
    "Hope you had a good weekend, and",
]

CUSTOM_GLYPHS = [
    "\u2764\ufe0f\u200d\U0001fa79",   # heart on fire bandage (ZWJ sequence)
    "\U0001F44B\U0001F3FD",            # waving hand, medium skin tone
    "\U0001F1EC\U0001F1E7",            # flag: United Kingdom
    "\u263a\ufe0f",
    "x",
    "\u200d",
]

DISPLAY_CASES = [
    ("\U0001F44B", "medium"),       # waving hand: modifier base
    ("\U0001F44B", "none"),
    ("\U0001F60A", "dark"),         # smiling face: not a modifier base
    ("\u270C", "light"),            # victory hand
    ("\U0001F9D1", "medium_dark"),
]

SIGNATURE_CASES = [
    dict(signoff="Kind regards,\n\nJohn Smith\n", profile=["John Smith", "Specialist and Superhero",
         "Data by day, defeating villains by night"], disclaimer="a disclaimer text goes here\n",
         include=True, ref="YyM4mRnjHQ", ref_only=False),
    dict(signoff="Kind regards,\n\nJohn Smith\n", profile=["John Smith"], disclaimer="text",
         include=False, ref="ABCDEFGHJK", ref_only=False),
    dict(signoff="Bye", profile=["Me"], disclaimer="Disclaimer", include=True, ref="ABCDEFGHJK",
         ref_only=True),
    dict(signoff="", profile=None, disclaimer="", include=True, ref="ABCDEFGHJK", ref_only=False),
    dict(signoff="\n\n", profile=["", "  "], disclaimer="   \n", include=True, ref="ABCDEFGHJK",
         ref_only=False),
    dict(signoff="Cheers\n\n\n", profile=["Line one", "", "Line three"], disclaimer="  spaced out  ",
         include=True, ref="ABCDEFGHJK", ref_only=False),
]

NOTE_TEXTS = [
    "Body text",
    "",
    "Trailing newlines\n\n\n",
    "Line one\r\nLine two",
    "Caf\u00e9 \u2615 and emoji \U0001F389",
    "x" * 100,
    "A long English paragraph that easily goes past the seventy-eight character limit of the policy.\n"
    "Second line.",
    "\u77ed\u3044" * 40,
    "Twelve lines of text that are long enough to force encoding past the limit, line 1\n" * 12,
    "Trailing space at the end of a very long line that is going to need soft line breaks   ",
    "Equals signs = everywhere = in a line that is long enough to wrap around the limit ===",
    "tab\tseparated\tvalues " * 6,
]

EML_HEADERS = [
    ("me@example.com", "Hello"),
    ("", ""),
    ("  me@example.com  ", "  Padded subject  "),
    ("me@example.com", "word " * 30),
    ("me@example.com", "Hello  double  spaces"),
    ("me@example.com", "Caf\u00e9 \u2615"),
    ("me@example.com", "\U0001F389\U0001F389 Party time"),
    ("me@example.com", "R\u00e9union de l\u2019\u00e9quipe du lundi matin \u00e0 propos du budget pr\u00e9visionnel"),
    ("J\u00f6hn Sm\u00efth <me@example.com>", "Hi"),
    ("\"Smith, John\" <me@example.com>", "Quoted display name"),
]

WHEN = [
    (datetime(2026, 9, 30, 10, 0, 0, tzinfo=timezone(timedelta(hours=1))), 3600),
    (datetime(2026, 1, 4, 23, 59, 7, tzinfo=timezone(timedelta(hours=-5, minutes=-30))), -19800),
    (datetime(2027, 2, 28, 0, 0, 0, tzinfo=timezone.utc), 0),
]


def _eml_cases():
    cases = []
    i = 0
    for n, (address, subject) in enumerate(EML_HEADERS):
        # Every body with the first header pair; three bodies with the rest.
        for text in NOTE_TEXTS if n == 0 else NOTE_TEXTS[:3]:
            when, offset = WHEN[i % len(WHEN)]
            data = note.build_note_eml(address, subject, text, "ABCDEFGHJK", when)
            head, _, body = data.partition(b"\n\n")
            values = [address.strip(), subject.strip()]
            header_lines = head.decode("ascii").split("\n")
            exact = all(v.isascii() and len(v) < 60 for v in values)
            cases.append(dict(
                address=address, subject=subject, text=text, ref="ABCDEFGHJK",
                timestamp=int(when.timestamp()), offset=offset,
                exact_headers=exact,
                eml=base64.b64encode(data).decode("ascii"),
                header_lines=header_lines,
                body=base64.b64encode(body).decode("ascii"),
            ))
            i += 1
    return cases


# -- workspace scenarios ------------------------------------------------------

FAVOURITES_CSV = (
    "id,label,char\r\n"
    "smiling_face_with_smiling_eyes,,\r\n"
    "waving_hand_sign,\"hello, there\",\r\n"
    "waving_hand_sign,duplicate ignored,\r\n"
    "custom_2764_fe0f_200d_1fa79,mended,\u2764\ufe0f\u200d\U0001fa79\r\n"
    "  thumbs_up_sign  ,  padded label  ,\r\n"
    "\r\n"
    ",no id,\r\n"
    "no_such_emoji_anywhere,orphan,\r\n"
    "face_with_tears_of_joy\r\n"
)

PHRASES_CSV = (
    "id,text\n"
    "thanks,Thanks very much for your help.\n"
    "multi,\"Line one\nLine two, with \"\"quotes\"\"\"\n"
    "spaces,   padded text   \n"
    ",no id is skipped\n"
    "follow_up,Just following up on my previous email.\n"
)

LEGACY_FAVOURITES_CSV = "id\r\nsmiling_face_with_smiling_eyes\r\nwaving_hand_sign\r\n"

SCENARIOS = [
    dict(
        name="read_and_mutate",
        files={
            "favourite_emoji.csv": FAVOURITES_CSV,
            "phrases.csv": PHRASES_CSV,
            "mailsigs/signoff.txt": "Kind regards,\r\n\r\nJohn Smith\r\n",
            "mailsigs/disclaimer.txt": "a disclaimer text goes here\n",
            "mailsigs/profiles/Zeta.txt": "Zeta\n\n\n",
            "mailsigs/profiles/alpha.txt": "Alpha One\r\nAlpha Two\r\n\r\n",
            "mailsigs/profiles/beta.TXT": "ignored: not .txt\n",
            "mailsigs/profiles/notes.md": "ignored\n",
        },
        ops=[
            ["add_favourite", "waving_hand_sign"],
            ["add_favourite", "thumbs_up_sign"],
            ["add_favourite", "grinning_face"],
            ["add_custom_favourite", "  \U0001F1EC\U0001F1E7  "],
            ["add_custom_favourite", "\U0001F1EC\U0001F1E7"],
            ["add_custom_favourite", "   "],
            ["set_favourite_label", "grinning_face", "  big grin, \"literally\"  "],
            ["set_favourite_label", "waving_hand_sign", "   "],
            ["set_favourite_label", "not_a_favourite", "ignored"],
            ["move_favourite", "grinning_face", -1],
            ["move_favourite", "smiling_face_with_smiling_eyes", -1],
            ["move_favourite", "face_with_tears_of_joy", 1],
            ["remove_favourite", "custom_2764_fe0f_200d_1fa79"],
            ["remove_favourite", "custom_2764_fe0f_200d_1fa79"],
            ["add_phrase", "Thanks very much for your help."],
            ["add_phrase", "  Thanks very much for your help, again and again and again.  "],
            ["add_phrase", "!!!"],
            ["add_phrase", "Réunion de l’équipe"],
            ["edit_phrase", "spaces", "  now edited  "],
            ["edit_phrase", "missing", "no change"],
            ["delete_phrase", "multi"],
            ["move_phrase", "follow_up", -1],
            ["move_phrase", "thanks", -1],
        ],
    ),
    dict(
        name="legacy_single_column",
        files={
            "favourite_emoji.csv": LEGACY_FAVOURITES_CSV,
            "phrases.csv": "id,text\r\n",
        },
        ops=[["add_custom_favourite", "\u263a\ufe0f"], ["set_favourite_label", "waving_hand_sign", "hi"]],
    ),
    dict(name="missing_files", files={}, ops=[]),
]

SCAFFOLD_FILES = [
    "favourite_emoji.csv", "phrases.csv", "mailsigs/signoff.txt",
    "mailsigs/disclaimer.txt", "mailsigs/profiles/default.txt",
]


def _snapshot(ws, root: Path):
    files = {}
    for p in sorted(root.rglob("*")):
        if p.is_file():
            files[str(p.relative_to(root))] = base64.b64encode(p.read_bytes()).decode("ascii")
    return dict(
        # Copies: later ops mutate these in place.
        favourite_ids=list(ws.favourite_ids),
        favourite_labels=dict(ws.favourite_labels),
        favourite_chars=dict(ws.favourite_chars),
        phrases=[[p.id, p.text] for p in ws.phrases],
        profiles=[[p.name, list(p.lines)] for p in ws.profiles],
        signoff=ws.signoff,
        disclaimer=ws.disclaimer,
        favourite_emoji=[e.id for e in ws.favourite_emoji()],
        custom_favourites=[[e.id, e.char, e.name] for e in ws.custom_favourites()],
        validate=ws.validate(),
        files=files,
    )


def _run_scenarios(catalogue):
    out = []
    for sc in SCENARIOS:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for rel, content in sc["files"].items():
                path = root / rel
                path.parent.mkdir(parents=True, exist_ok=True)
                with open(path, "w", encoding="utf-8", newline="") as fh:
                    fh.write(content)
            ws = Workspace(str(root), catalogue)
            before = _snapshot(ws, root)
            results = []
            for op, *args in sc["ops"]:
                results.append(getattr(ws, op)(*args))
            after = _snapshot(ws, root)
            ws.scan()
            rescanned = _snapshot(ws, root)
            out.append(dict(name=sc["name"], files=sc["files"], ops=sc["ops"],
                            before=before, results=[_result(r) for r in results],
                            after=after, rescanned=rescanned))
    return out


def _result(r):
    if isinstance(r, models.Phrase):
        return [r.id, r.text]
    return r


def _scaffold(catalogue):
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        ws = Workspace(str(root), catalogue)
        ws.ensure_scaffold()
        ws.scan()
        return _snapshot(ws, root)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--python-repo", default=os.environ.get("QDVC_PYTHON_REPO"),
                    help="checkout of qdvc-nice-mail (or set QDVC_PYTHON_REPO)")
    args = ap.parse_args()
    if not args.python_repo:
        ap.error("--python-repo is required (or set QDVC_PYTHON_REPO)")
    _import_reference(Path(args.python_repo).expanduser().resolve())

    catalogue = emoji_mod.EmojiCatalogue()
    fixtures = dict(
        unicode_version=unicodedata.unidata_version,
        catalogue=[[e.id, " ".join(f"{ord(c):X}" for c in e.char), e.name] for e in catalogue.all()],
        emoji_id=[[s, naming.emoji_id(s)] for s in EMOJI_ID_INPUTS],
        custom=[[g, naming.custom_emoji_id(g), catalogue.make_custom(g).name] for g in CUSTOM_GLYPHS],
        display=[[c, t, emoji_mod.Emoji(id="x", char=c, name="x").display(t)] for c, t in DISPLAY_CASES],
        search=[[q, [e.id for e in catalogue.search(q)][:40], len(catalogue.search(q))]
                for q in ["smiling", "  HAND  ", "zzzz", "arrow"]],
        signature=[dict(case, out=mailsig.assemble_signature(
            case["signoff"],
            models.Profile(name="p", lines=case["profile"]) if case["profile"] is not None else None,
            case["disclaimer"], case["include"], case["ref"], case["ref_only"])) for case in SIGNATURE_CASES],
        note_body=[[t, note.note_body(t, "ABCDEFGHJK")] for t in NOTE_TEXTS],
        eml=_eml_cases(),
        filename=[[int(w.timestamp()), off, note.default_note_filename("ABCDEFGHJK", w)] for w, off in WHEN],
        scenarios=_run_scenarios(catalogue),
        scaffold=_scaffold(catalogue),
    )
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(fixtures, ensure_ascii=False, indent=1, sort_keys=True) + "\n",
                   encoding="utf-8")
    print(f"Wrote {OUT} (Unicode {unicodedata.unidata_version}, "
          f"{len(fixtures['catalogue'])} catalogue entries)")


if __name__ == "__main__":
    main()

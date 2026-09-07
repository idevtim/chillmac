---
name: release-notes
description: Write the release notes file for a new ChillMac version. Use when cutting a release, after bumping the version in Info.plist, or when the user asks for release notes or runs /release-notes.
---

# Release notes

Write `release-notes/v<version>.md`. Take the version from `$ARGUMENTS` if given (with or
without a leading `v`), otherwise read it:

```bash
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" ChillMac/Info.plist
```

If that version already has a notes file, say so and ask before overwriting it.

## Why the format is what it is

The same file is consumed twice, verbatim, by `scripts/build-dmg.sh`:

- **Sparkle's in-app update prompt**, embedded as markdown into `appcast.xml` via
  `generate_appcast --embed-release-notes`. It renders in a small dialog the user reads
  before accepting an update.
- **The GitHub release body**, via `gh release create --notes-file`.

The build fails its pre-flight if `release-notes/v$VERSION.md` is missing, so the filename
has to match the Info.plist version exactly.

Both consumers supply their own title (`gh release create --title "v$VERSION"`), so **the
file must not contain an H1**. Start at `##`.

## Gathering material

Do not guess at the changelog. Read what actually changed:

```bash
git log --oneline "$(git describe --tags --abbrev=0)"..HEAD
git diff --stat "$(git describe --tags --abbrev=0)"..HEAD
```

Read the diff for anything you cannot describe confidently from the commit subject. Every
bullet must correspond to a real change in that range. If uncommitted work is going into
this release, include `git status` and the working diff too.

## Format

Open with `## Highlights` and one short prose paragraph, in plain language, saying what this
release means for someone using the app. A small patch can skip the heading and open with a
single sentence instead (see `v1.8.2.md`).

Then group into sections, using only these headings as needed: `## Added`, `## Fixed`,
`## Improvements`, `## Changed`. Omit any that would be empty.

Bullets lead with a bold claim, ended by a period, then a sentence or two of explanation:

```markdown
- **Battery health percentage.** ChillMac was calculating it from the raw gauge reading and
  coming out several percent low. It now reads the same value System Settings shows
```

## Rules

- **No H1.** Both consumers add the title themselves.
- **No em dashes**, in the summary or the bullets. Use a comma, a colon, or a new sentence.
  Notes through v1.8.1 used them; v1.8.2 onward does not. Match v1.8.2.
- **Short.** Aim for under 15 lines. This is read in an update dialog, not a changelog page.
- **User-facing, not implementation-facing.** Say what the user saw go wrong and what they
  will see now. A brief why is welcome when it explains the symptom, but no file names, type
  names, or function names.
- **Silent failures are worth a sentence of reassurance.** When a bug meant something looked
  like it worked but did not, say plainly what was and was not affected. `v1.8.1.md` is the
  model: it states that monitoring was always accurate and only fan control was broken.
- **Lead with the fix users actually noticed**, not the largest diff.

## Call out anything that interrupts the update

If this release requires a manual step, put it in the Highlights paragraph, not in a bullet
near the bottom. People who do not read it will think the release broke something. This
applies when:

- `kHelperVersion` in `Shared/HelperProtocol.swift` changed. The daemon gets unregistered and
  re-registered, so the user has to approve ChillMac again under Login Items & Extensions.
- Sparkle's updater or signing key changed, or the release cannot be installed by the
  previous version's updater and has to be installed by hand.

Check with:

```bash
git diff "$(git describe --tags --abbrev=0)"..HEAD -- Shared/HelperProtocol.swift
```

`v1.8.0.md` shows the tone: state the interruption in the second paragraph, say why, and say
that later releases go back to one click.

## Finishing

Write the file, then show it to the user in full and stop. Do not build, tag, commit, or
touch `appcast.xml`; `scripts/build-dmg.sh` regenerates the appcast at release time and the
appcast is committed separately afterwards.

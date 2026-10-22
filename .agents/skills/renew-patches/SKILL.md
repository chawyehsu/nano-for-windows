---
name: renew-patches
description: Renew the win32 patch set in patches/latest/ after a new GNU nano
  release, using the upstream diff from the release-tracking issue. Only fixes
  existing patches; never invents new ones.
---

# Renew the patch set for a new GNU nano release

`patches/latest/` is the **working patch set**. When upstream releases a new
version, the patches in it usually no longer apply. This skill snapshots the
current working set into `patches/<old-version>/`, then repairs every patch in
`patches/latest/` against the new upstream sources until the whole set applies
and builds.

Never add a patch. Never renumber filenames. Deletions are proposed to the
human, never performed unilaterally.

## Prerequisites

- `gh` authenticated (reads the release-tracking issue, creates nothing).
- `jj`, `git`, `pixi`, `tar` on PATH.
- You are in a clean jj working copy. Check `jj status`; if it is dirty, stop
  and ask the human to commit or abandon first.

## Procedure

### 1. Locate the release-tracking issue

```
gh issue list --label upstream-release --state open --json number,title
```

Exactly one open issue, titled `GNU nano <new> released upstream`. If there are
several, take the **highest** version and report which others are being skipped
(they stay open; the human closes them).

Ask the human to confirm `<new>` before continuing.

### 2. Read the versions

```
gh issue view <number> --json title,body
```

From the body's diff link
`https://github.com/ahjragaas/nano/compare/v<old>...v<new>` take `<old>` and
`<new>`. Cross-check `<new>` against the issue title.

`patches/<old>` must not exist yet. If it does, that release was already
snapshotted: the working set now targets a later version, and this issue is
stale. Stop and report; do not renew and do not delete anything.

### 3. Snapshot

```
pwsh -nop .agents/skills/renew-patches/scripts/invoke-patch-renew.ps1 -OldVersion <old>
```

Copies `patches/latest/*.patch` verbatim into `patches/<old>/`. The script
skips an identical existing snapshot and fails on a differing one, so it is safe
to re-run.

Do not build the snapshot. Frozen patch sets are verified manually when needed:

```
pwsh -nop .agents/skills/renew-patches/scripts/verify-patches.ps1 -Version <old>
```

### 4. Fetch the upstream diff and slice it

```
curl -L -o .cache/renew-<new>/upstream.diff \
  https://github.com/ahjragaas/nano/compare/v<old>...v<new>.diff
pwsh -nop .agents/skills/renew-patches/scripts/get-upstream-slices.ps1 \
  -Diff .cache/renew-<new>/upstream.diff \
  -PatchesDir patches/latest \
  -OutDir .cache/renew-<new>/slices
```

Each patch gets `.cache/renew-<new>/slices/<patch-stem>.diff`, holding only the
upstream hunks that touch the same files. Read the slice, never the whole
upstream diff. A patch whose slice is empty was not touched by upstream, so a
failure there has another cause.

### 5. Repair loop

Repeat until a verification pass is green:

1. `pwsh -nop .agents/skills/renew-patches/scripts/verify-patches.ps1 -Version <new> -WorkingSet`
2. Take the first failing patch. Read its slice.
3. Edit the patch's hunks in `patches/latest/<file>` so they apply to the new
   sources. Keep `From`, `Date` and `Signed-off-by` exactly as they are. Update
   the `index a..b` lines when they no longer match.
4. Retry the same patch up to 3 times.

`-WorkingSet` is required here: the patches under test are `patches/latest`,
while `-Version <new>` says which release to build them against. Both halves are
explicit, so a pass cannot be produced by building the wrong sources.

**If the first verification is already green with no edits made, the renewal is
done.** Upstream sometimes leaves the working set untouched; there is nothing to
repair, and an unchanged `patches/latest` is the correct result. Say so in the
report and stop.

An empty `jj diff patches/latest` is only suspicious in the other direction: if
verification did *not* pass, an unchanged set means the failure has a cause the
repair loop cannot address, so report it rather than looping.

When the loop is green, the renewal is done.

## Failure classes

**Mechanical** — hunk context drifted, surrounding lines moved, `git am`
produced a `.rej`. Retry, guided by the slice.

**Semantic** — the symbol the patch touches no longer exists, or upstream
already does what the patch does. Do not retry; retrying pushes you to rewrite
the patch into something it is not.

When you stop, add a `## Blocked` section to `.cache/renew-<new>/report.md`
covering, per blocked patch:

- the colliding upstream hunks (path to the slice),
- what the patch intended, in one sentence,
- two or three concrete options: delete it, relocate it to a named replacement
  symbol, or escalate as needing a human rewrite.

Then ask the human which option to take. Apply their answer in the same run and
continue. If no option is workable, restore and stop.

## Report

`.cache/renew-<new>/report.md` has two sections, written as you go:

- `## Blocked` — anything you stopped on, with the options you offered.
- `## Changes` — per patch, one line: what you changed and why. List every file
  whose bytes changed.

Print `## Blocked` to chat when it appears, and a digest of `## Changes` at the
end.

## Rules

- **Never add a patch.** A fix upstream needs is out of scope; say so and stop.
- **Never renumber filenames.** A deleted patch leaves its prefix unused.
  Filenames denote patch lineage, not position in a set.
- **Subjects follow apply order.** After a deletion, the surviving patches must
  read `[PATCH k/N]`, renumbered from 1, with `N` the new count. Keep the
  original subject text after the closing bracket.
- **Snapshot before editing.** Never touch `patches/latest/` before the snapshot
  exists.
- **All or nothing.** If the set cannot be made green, restore it
  (`jj restore -r @ patches/latest`) and report. A half-renewed set silently
  breaks `setup.ps1`, which prefers a versioned directory over `latest/`.
- **Do not commit.** Leave the edits in the working copy; the human reviews with
  `jj diff`.

## Manual commands

Verify a frozen patch set (never automatic):

```
pwsh -nop .agents/skills/renew-patches/scripts/verify-patches.ps1 -Version 9.2
```

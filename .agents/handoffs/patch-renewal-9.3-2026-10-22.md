# Handoff: Patch renewal for version 9.3 on 2026-10-22

Status: **done, verified.**

Traps hit during this renewal, for the next agent doing a `renew-patches` run.
Read these first.

- **Verify with the real script early.** `verify-patches.ps1 -Version <new> -WorkingSet`
  reports one failing patch at a time; do not eyeball a patch into place.
- **Never edit a patch with `Set-Content`/`Out-File` in PowerShell.** Both add a
  BOM, CRLF endings, or a trailing newline that git rejects with
  `corrupt patch`. Use `python` byte-level edits, or generate the hunks with
  `git diff` and splice them in.
- **Prefer regenerating hunks to hand-editing them.** Apply the patch set up to
  the failing patch in a scratch tree, make the intended source edit, then take
  the `git diff` of those files as the new hunks. Hand-counted `@@` lengths are
  the single most common source of `corrupt patch` / `fragment without header`.
- **Do not overwrite a patch with only the diff of files you touched.** A patch
  often carries hunks for files that need no renewal (`0011` rewrites the whole
  `parse_kbinput` modifier block). Splicing a partial diff silently deletes
  those hunks. Rebase the previous snapshot from `patches/<old>/` instead.
- **The patch set is cumulative.** Regenerate against a tree with patches
  `0001..N-1` already applied, not pristine upstream, or the diff re-adds work
  an earlier patch already did (this is how `0006` first grew `0005`'s hunks).
- **Upstream context changes are the usual cause of a reject, not drift.** Look
  for what the *previous* patches did to the same lines. In 9.3, `0002` removed
  the VTE block that used to sit after `#endif /* __linux__ */`, so `0011`'s
  trailing context had to point at `switch (keycode) {` instead.
- **Check preprocessor balance after a reject.** A hunk that removes only the
  closing `#endif` still applies but produces `unterminated #ifdef` at build
  time. Run a quick `#if`/`#endif` stack check on the file; a balanced pristine
  file plus an unbalanced patched one means the hunk took the wrong half of the
  pair.
- **Upstream signature changes make hunks fail on their own.** 9.3 dropped the
  trailing `0` argument from `add_to_sclist`; the `0011` hunk had to be
  rewritten rather than renumbered.
- **`curl` may not reach github.com.** `gh api repos/<upstream>/compare/v<old>...v<new>
  -H "Accept: application/vnd.github.v3.diff"` returns the same diff.
- **`verify-patches.ps1` prints git's colour escapes red.** `Select-String
  'error'` also matches warnings; filter on `: error:` instead.
- **The verify workspace needs `jj workspace forget verify-nano-<new>`** before
  re-running, otherwise jj refuses to recreate it.

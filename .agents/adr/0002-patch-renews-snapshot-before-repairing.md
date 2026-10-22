# Patch renews snapshot before repairing, and never infer the build target

Renewing the win32 patches for a new GNU nano release is a single atomic operation with a fixed order. `patches/latest/` is first snapshotted verbatim into `patches/<old-version>/`, skipping files that already match and refusing to overwrite a differing frozen set. Only then are the patches repaired against the upstream diff, until a clean `git am` and a green `pixi run build` pass.

Verification always names the release to build against explicitly. `verify-patches.ps1 -Version 9.3` verifies `patches/9.3`; `-Version 9.3 -WorkingSet` verifies `patches/latest` against 9.3. The build target is never inferred from the patch set being tested, so a green pass always means the named release was built. We rejected a version marker file in `latest/` for this reason: any stored value can disagree with the patches it sits next to, and a verification step that trusts it can pass while building the wrong sources.

The same reasoning rejects falling back to `patches/latest` when `patches/<version>/` is absent: silently verifying a different set than the one named is the failure mode this design exists to prevent. The script fails and lists the patch sets that do exist.

A renew never adds a patch and never renumbers filenames. Deleting a patch is proposed to a human, never performed by the tool. Filenames are stable identities — a deleted patch leaves its prefix unused — while the `[PATCH k/N]` subject counts track apply order over the survivors, so `N` shrinks on deletion without any file being renamed.

**Status**: accepted

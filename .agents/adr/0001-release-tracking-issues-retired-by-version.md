# Release-tracking issues are retired by exact upstream-version match

When `release.ps1` creates a GitHub release, it closes the open `upstream-release` tracking issue whose version equals the released version — and no other. The released tag carries a conda build suffix (`v8.2-1`) while tracking issues are keyed to clean upstream versions (`8.2`), so the tag is normalized and the issue title is parsed (`^GNU nano ([\d.]+) released upstream$`) and compared as typed `[version]` values.

We rejected closing all open tracking issues (it wrongly retires issues for versions not yet shipped) and substring title matching (it can false-positive across version boundaries, e.g. `8.2` vs `8.25`). Retirement happens only when a new release is created by this script — not on the "already on GitHub" early-exit — and the issue is commented before being closed, mirroring the dry-run/fail-hard patterns of the rest of the script.

**Status**: accepted

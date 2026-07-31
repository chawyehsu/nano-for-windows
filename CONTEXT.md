# nano-for-windows Release

The automation that watches GNU nano upstream, re-publishes conda packages as GitHub Releases, and tracks out-of-date versions as issues.

## Language

**Upstream nano release**:
A GNU nano version announced on nano-editor.org, parsed from the NEWS file by `check-upstream.ps1`.

**Conda package**:
A nano-for-windows package published on Anaconda.org, one per platform (win-64, win-arm64), identified by a version and an optional conda build number.
_Avoid_: conda release

**GitHub release**:
A nano-for-windows release on GitHub Releases, tagged `v<version>`, carrying the re-uploaded conda and zip assets. The tag may include a conda build suffix (e.g. `v8.2-1`).

**Release-tracking issue**:
An issue labeled `upstream-release`, titled `GNU nano <version> released upstream`, opened by `check-upstream.ps1` when upstream is ahead of GitHub, requesting a new release.
_Avoid_: upstream issue, nag issue

**Retire**:
To close a release-tracking issue — after commenting a reference to the GitHub release — once the matching version has shipped as a GitHub release.
_Avoid_: close out, resolve

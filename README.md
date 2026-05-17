# GNU nano for Windows

> Windows port of the [GNU nano text editor], made with the conda-forge ecosystem

[![Release](https://github.com/chawyehsu/nano-for-windows/actions/workflows/release.yml/badge.svg)](https://github.com/chawyehsu/nano-for-windows/actions/workflows/release.yml) [![Downloads](https://img.shields.io/github/downloads/chawyehsu/nano-for-windows/total?style=flat&logo=github)](https://github.com/chawyehsu/nano-for-windows/releases) [![Conda Version](https://img.shields.io/conda/vn/chawyehsu/nano.svg)](https://anaconda.org/chawyehsu/nano) [![GitHub Release](https://img.shields.io/github/v/release/chawyehsu/nano-for-windows.svg?logo=github)](https://github.com/chawyehsu/nano-for-windows/releases)

## Getting Started

### Features

- Unicode/**UTF-8** support (built against UCRT)
- Syntax highlighting support
- nanorc support and system-wide nanorc discovery
- **Spell checker** and **Formatter** support (only external spell checkers)
- **Full keyboard binding** support
  1. For `M-X` rebindings, full support for all characters in
     the ASCII range is now available. This means you can configure
     and use key combinations such as `M-<`, `M-=`, `M-@`, etc.,
     with more consistent key bindings with the nano on Unix.
  2. For `M-X` rebindings, only the left `Alt` key is now captured.
     This means you can still type less frequently used characters
     using the right `Alt` as `AltGr` key even if you have configured
     many key combos of `Alt`. This is especially crucial for users
     with keyboard layouts such as US International and German.
  3. Most key combinations related to `Backspace`, `Del`, and the
     arrow keys now behave consistently with the nano on Unix.
- `positionlog` support (Saved anchors restored when file is reopened, v8.5+)
- Copy/paste support
- Mouse support

### Install

Pre-built artifacts of **nano-for-windows** are available on chawyehsu's conda
channel. You can install it with [pixi] or conda/mamba.

```shell
pixi global install nano -c chawyehsu -c conda-forge
```

Or you can install it with [Scoop](https://scoop.sh/):

```plain
scoop bucket add dorado https://github.com/chawyehsu/dorado
scoop install dorado/nano
```

Or you may download the pre-built artifact from [GitHub Releases], extract the
files to a directory and add the `bin` directory to your `PATH` environment variable.

Then run `nano --version` to verify the installation.

## Development

Prerequisites: Git, [pixi], [Jujutsu]

```shell
jj git clone https://github.com/chawyehsu/nano-for-windows
cd nano-for-windows
pixi install
pixi run setup
# First build
pixi run build
# Make new patches to the source code, then rebuild
pixi run rebuild
```

## Knowledge

GNU nano has been ported to Windows by different developers at different times.
However, existing ports are either no longer maintained or rarely updated, or
they contain problems that the porters were unwilling to address. Therefore, I
decided to port and maintain my own edition.

### Build Pipeline

The pre-built artifacts provided in this repository are built with the conda-forge
ecosystem, and then reuploaded to GitHub Releases. The recipe is available on the
repo [chawyehsu/conda-recipes], build logs are also available there.

### Prior work

- [Official build for Windows]
- [lhmouse/nano-win]
- [okibcn/nano-for-windows]

## License

**nano-for-windows** © [Chawye Hsu](https://github.com/chawyehsu). Released under the [GPL-3.0-or-later](LICENSE) license.

> [Blog](https://chawyehsu.com) · GitHub [@chawyehsu](https://github.com/chawyehsu) · Twitter [@chawyehsu](https://twitter.com/chawyehsu)

[GNU nano text editor]: https://www.nano-editor.org
[GitHub Releases]: https://github.com/chawyehsu/nano-for-windows/releases
[pixi]: https://pixi.sh
[Jujutsu]: https://www.jj-vcs.dev/
[chawyehsu/conda-recipes]: https://github.com/chawyehsu/conda-recipes/tree/main/nano
[Official build for Windows]: https://www.nano-editor.org/dist/win32-support/
[lhmouse/nano-win]: https://github.com/lhmouse/nano-win
[okibcn/nano-for-windows]: https://github.com/okibcn/nano-for-windows

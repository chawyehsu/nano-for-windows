# GNU nano for Windows

> Windows port of the [GNU nano text editor], made with the conda-forge ecosystem

[![Downloads](https://img.shields.io/conda/dn/chawyehsu/nano.svg)](https://anaconda.org/chawyehsu/nano) [![Version](https://img.shields.io/conda/vn/chawyehsu/nano.svg)](https://anaconda.org/chawyehsu/nano)

## Getting Started

### Install

Pre-built artifacts of **nano-for-windows** are available on chawyehsu's conda
channel. You can install it with [pixi] or conda/mamba.

```shell
pixi global install nano -c chawyehsu
```

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

### Prior work

- [Official build for Windows]
- [lhmouse/nano-win]
- [okibcn/nano-for-windows]

## License

**nano-for-windows** © [Chawye Hsu](https://github.com/chawyehsu). Released under the [GPL-3.0-or-later](LICENSE) license.

> [Blog](https://chawyehsu.com) · GitHub [@chawyehsu](https://github.com/chawyehsu) · Twitter [@chawyehsu](https://twitter.com/chawyehsu)

[GNU nano text editor]: https://www.nano-editor.org
[pixi]: https://pixi.sh
[Jujutsu]: https://www.jj-vcs.dev/
[Official build for Windows]: https://www.nano-editor.org/dist/win32-support/
[lhmouse/nano-win]: https://github.com/lhmouse/nano-win
[okibcn/nano-for-windows]: https://github.com/okibcn/nano-for-windows

# GNU nano for Windows

> Windows port of the GNU nano text editor, made with the conda-forge ecosystem

[![Downloads](https://img.shields.io/conda/dn/chawyehsu/nano.svg)](https://anaconda.org/chawyehsu/nano) [![Version](https://img.shields.io/conda/vn/chawyehsu/nano.svg)](https://anaconda.org/chawyehsu/nano)

## Getting Started

### Install

Pre-built artifacts of **nano-for-windows** are available on chawyehsu's conda channel. You can install it with [pixi] or conda/mamba.

```shell
pixi global install nano -c chawyehsu
```

## Development

Prerequisites: Git, [pixi], [Jujutsu]

```shell
jj git clone https://github.com/chawyehsu/nano-for-windows
cd nano-for-windows
pixi install
pixi run setup
```

## License

**nano-for-windows** © [Chawye Hsu](https://github.com/chawyehsu). Released under the [GPL-3.0-or-later](LICENSE) license.

> [Blog](https://chawyehsu.com) · GitHub [@chawyehsu](https://github.com/chawyehsu) · Twitter [@chawyehsu](https://twitter.com/chawyehsu)

[pixi]: https://pixi.sh
[Jujutsu]: https://www.jj-vcs.dev/

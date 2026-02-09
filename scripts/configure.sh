#!/bin/bash
set -euo pipefail

project_root="$(dirname "${BASH_SOURCE[0]}")/../"

pushd "$project_root"

if [[ -f Makefile ]]; then
    echo "Makefile already exists. Skipping configuration."
    exit 0
fi

ostype="$(uname -s)"
# convert backslashes to forward slashes for MSYS2
# shellcheck disable=SC1003
LIBRARY_PREFIX="$(echo "${CONDA_PREFIX}" | tr '\\' '/')"

if [[ "${ostype}" =~ MSYS_NT-* ]]; then
    export CFLAGS="${CFLAGS:-} -DPDC_FORCE_UTF8 -DPDC_NCMOUSE"
    export LDFLAGS="${LDFLAGS:-} -L$LIBRARY_PREFIX/lib -static"
    export NCURSESW_CFLAGS="-I$LIBRARY_PREFIX/include -DNCURSES_STATIC -DENABLE_MOUSE"
    export NCURSESW_LIBS="-l:pdcurses.a -lwinmm"

    export HOST=x86_64-w64-mingw32
    export BUILD=x86_64-w64-mingw32

    ./configure \
        --build="${BUILD}" \
        --host="${HOST}" \
        --disable-dependency-tracking \
        --enable-utf8 \
        --disable-{nls,browser}
else
    ./configure \
        --disable-dependency-tracking \
        --build="${BUILD}" \
        --host="${HOST}"
fi

popd

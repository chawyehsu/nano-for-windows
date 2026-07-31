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
    export LDFLAGS="${LDFLAGS:-} -L$LIBRARY_PREFIX/lib -static"
    # `PDC_NCMOUSE` to enable ncurses-compatible mode mouse API
    export NCURSESW_CFLAGS="-I$LIBRARY_PREFIX/include -I$LIBRARY_PREFIX/include/pdcurses -DPDC_NCMOUSE"
    export NCURSESW_LIBS="-lpdcurses -lwinmm"

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

#!/bin/sh

# This file is to bootstrap the TCC thing on WSL
# Essentially:
# Build the host TCC compilers (for x86_64 Linux and Windows)
# Build the runtime libraries for embedded libtcc (Linux and Windows)
# Build the modified TCC libtcc (static library) as ONE_SOURCE

# Exit on first error
set -e

verbose_do()
{
  echo "$@"
  "$@"
}

# Make sure we are in the right directory
if [ ! -f "src/configure" ] && [ ! -d "bin" ]; then
  echo "Error: This script should be run from the tcc-vio directory"
  echo "Current directory: $PWD"
  echo "Expected to find: src/configure and bin/"
  exit 1
fi

TCC_ROOT_DIR="$PWD"
TCC_TRUNK_DIR="$TCC_ROOT_DIR/src-mini-trunk"
TCC_PATCH_DIR="$TCC_ROOT_DIR/src"
TCC_HOST_BIN_DIR="$TCC_ROOT_DIR/bin/tcc-host"
TCC_LIBTCC_DIR="$TCC_ROOT_DIR/bin/libtcc-x86_64-linux-static"
TCC_LIBTCC_WIN_DIR="$TCC_ROOT_DIR/bin/libtcc-x86_64-windows-static"
TCC_LINUX_RUNTIME_DIR="$TCC_ROOT_DIR/bin/tcc-x86-64-linux-runtime"
TCC_WIN_RUNTIME_DIR="$TCC_ROOT_DIR/bin/tcc-x86-64-windows-runtime"

echo "BUILDING ============="
echo "ROOT     $TCC_ROOT_DIR"
echo "TRUNK    $TCC_TRUNK_DIR"
echo "PATCH    $TCC_PATCH_DIR"
echo "HOST-BIN $TCC_HOST_BIN_DIR"
echo "LIBTCC   $TCC_LIBTCC_DIR"
echo "LIBTCC-W $TCC_LIBTCC_WIN_DIR"
echo "LINUX-RT $TCC_LINUX_RUNTIME_DIR"
echo "WIN-RT   $TCC_WIN_RUNTIME_DIR"
echo "##"

# Temporary copy the config
verbose_do cp libtcc-config.h src/config.h

# Step 1: Build host compilers from trunk (we need these to compile runtime libraries)
verbose_do mkdir -p "$TCC_HOST_BIN_DIR"
verbose_do cd "$TCC_HOST_BIN_DIR"
verbose_do ../../src-mini-trunk/configure --enable-cross
verbose_do make TCC_X="x86_64 x86_64-win32" -j16

# Step 3: Generate tccdefs_.h for modified source
echo "Generating tccdefs_.h for modified source..."
verbose_do mkdir -p "$TCC_LIBTCC_DIR"
verbose_do cd "$TCC_LIBTCC_DIR"
verbose_do mkdir -p include

# Generate tccdefs_.h from the modified source using host's c2str.exe
verbose_do "$TCC_HOST_BIN_DIR/c2str.exe" "$TCC_PATCH_DIR/include/tccdefs.h" include/tccdefs_.h

# Also copy the original tccdefs.h for reference
verbose_do cp "$TCC_PATCH_DIR/include/tccdefs.h" include/

# Step 4: Build ONE_SOURCE static libtcc from modified source
echo "Building ONE_SOURCE embedded static libtcc from modified source..."

# For ONE_SOURCE, we need to compile tcc.c with -DONE_SOURCE=1
# This will include all other source files through #includes
echo "Compiling ONE_SOURCE libtcc (tcc.c with -DONE_SOURCE=1)..."
verbose_do gcc -c "$TCC_PATCH_DIR/tcc.c" -DONE_SOURCE=1 -Iinclude -I"$TCC_PATCH_DIR" -Wall -O2 -Wdeclaration-after-statement -Wno-unused-result -o tcc.o

# Create static library (this is your embedded ONE_SOURCE libtcc.a)
echo "Creating ONE_SOURCE static libtcc.a for embedding..."
verbose_do ar rcs libtcc.a tcc.o

# Step 4w: Build ONE_SOURCE static libtcc for Windows using cross compiler
echo "Building ONE_SOURCE embedded static libtcc for Windows..."
verbose_do mkdir -p "$TCC_LIBTCC_WIN_DIR"
verbose_do cd "$TCC_LIBTCC_WIN_DIR"
verbose_do mkdir -p include

# Generate tccdefs_.h for modified source
verbose_do "$TCC_HOST_BIN_DIR/c2str.exe" "$TCC_PATCH_DIR/include/tccdefs.h" include/tccdefs_.h

# Also copy the original tccdefs.h for reference
verbose_do cp "$TCC_PATCH_DIR/include/tccdefs.h" include/

# Cross compile for Windows
echo "Compiling ONE_SOURCE libtcc for Windows..."
verbose_do x86_64-w64-mingw32-gcc -c "$TCC_PATCH_DIR/tcc.c" -DONE_SOURCE=1 -DTCC_TARGET_PE -DTCC_TARGET_X86_64 -Iinclude -I"$TCC_PATCH_DIR" -Wall -O2 -Wdeclaration-after-statement -Wno-unused-result -o tcc.o

# Create static library
echo "Creating ONE_SOURCE static libtcc.a for Windows..."
verbose_do x86_64-w64-mingw32-ar rcs libtcc.a tcc.o

# Step 5: Create runtime library for Linux (libtcc1.a)
echo "Building runtime library for Linux (libtcc1.a)..."
verbose_do mkdir -p "$TCC_LINUX_RUNTIME_DIR"
verbose_do cd "$TCC_LINUX_RUNTIME_DIR"
verbose_do mkdir -p include

# Generate tccdefs_.h for Linux runtime
verbose_do "$TCC_HOST_BIN_DIR/c2str.exe" "$TCC_PATCH_DIR/include/tccdefs.h" include/tccdefs_.h

# Also copy the original tccdefs.h for reference
verbose_do cp "$TCC_PATCH_DIR/include/tccdefs.h" include/

# Use x86_64 cross compiler to build Linux runtime from modified source
echo "Compiling Linux runtime files..."
verbose_do "$TCC_HOST_BIN_DIR/x86_64-tcc" -c "$TCC_PATCH_DIR/lib/libtcc1.c" -B"$TCC_TRUNK_DIR" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -o libtcc1.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-tcc" -c "$TCC_PATCH_DIR/lib/stdatomic.c" -B"$TCC_TRUNK_DIR" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -o stdatomic.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-tcc" -c "$TCC_PATCH_DIR/lib/atomic.S" -B"$TCC_TRUNK_DIR" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -o atomic.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-tcc" -c "$TCC_PATCH_DIR/lib/builtin.c" -B"$TCC_TRUNK_DIR" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -o builtin.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-tcc" -c "$TCC_PATCH_DIR/lib/alloca.S" -B"$TCC_TRUNK_DIR" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -o alloca.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-tcc" -c "$TCC_PATCH_DIR/lib/alloca-bt.S" -B"$TCC_TRUNK_DIR" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -o alloca-bt.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-tcc" -c "$TCC_PATCH_DIR/lib/dsohandle.c" -B"$TCC_TRUNK_DIR" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -o dsohandle.o

# Build support files (but don't include them in libtcc1.a)
verbose_do "$TCC_HOST_BIN_DIR/x86_64-tcc" -c "$TCC_PATCH_DIR/lib/tcov.c" -B"$TCC_TRUNK_DIR" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -o tcov.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-tcc" -c "$TCC_PATCH_DIR/lib/runmain.c" -B"$TCC_TRUNK_DIR" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -o runmain.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-tcc" -c "$TCC_PATCH_DIR/lib/bt-exe.c" -B"$TCC_TRUNK_DIR" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -o bt-exe.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-tcc" -c "$TCC_PATCH_DIR/lib/bt-log.c" -B"$TCC_TRUNK_DIR" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -o bt-log.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-tcc" -c "$TCC_PATCH_DIR/lib/bcheck.c" -B"$TCC_TRUNK_DIR" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -bt -o bcheck.o

# Create libtcc1.a for Linux (unprefixed - for embedded use)
echo "Creating libtcc1.a for Linux..."
verbose_do ar rcs libtcc1.a libtcc1.o stdatomic.o atomic.o builtin.o alloca.o alloca-bt.o dsohandle.o

# Step 6: Create runtime library for Windows (libtcc1.a)
echo "Building runtime library for Windows (libtcc1.a)..."
verbose_do mkdir -p "$TCC_WIN_RUNTIME_DIR"
verbose_do cd "$TCC_WIN_RUNTIME_DIR"
verbose_do mkdir -p include
verbose_do mkdir -p lib

# Generate tccdefs_.h for Windows runtime
verbose_do "$TCC_HOST_BIN_DIR/c2str.exe" "$TCC_PATCH_DIR/include/tccdefs.h" include/tccdefs_.h

# Merge core headers into the runtime include directory
echo "Merging core headers from $TCC_PATCH_DIR/include..."
verbose_do cp -rf "$TCC_PATCH_DIR/include"/* include/

# Merge Win32-specific headers into the runtime include directory
echo "Merging Win32 headers from $TCC_PATCH_DIR/win32/include..."
verbose_do cp -rf "$TCC_PATCH_DIR/win32/include"/* include/

# Copy Win32 .def files from $TCC_PATCH_DIR/win32/lib
echo "Copying Win32 .def files from $TCC_PATCH_DIR/win32/lib to lib/..."
verbose_do cp "$TCC_PATCH_DIR/win32/lib"/*.def lib/

# Use x86_64-win32 cross compiler to build Windows runtime from modified source
echo "Compiling Windows runtime files..."
verbose_do "$TCC_HOST_BIN_DIR/x86_64-win32-tcc" -c "$TCC_PATCH_DIR/lib/libtcc1.c" -B"$TCC_TRUNK_DIR/win32" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -I"$TCC_PATCH_DIR/win32/include" -o libtcc1.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-win32-tcc" -c "$TCC_PATCH_DIR/lib/stdatomic.c" -B"$TCC_TRUNK_DIR/win32" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -I"$TCC_PATCH_DIR/win32/include" -o stdatomic.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-win32-tcc" -c "$TCC_PATCH_DIR/lib/atomic.S" -B"$TCC_TRUNK_DIR/win32" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -I"$TCC_PATCH_DIR/win32/include" -o atomic.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-win32-tcc" -c "$TCC_PATCH_DIR/lib/builtin.c" -B"$TCC_TRUNK_DIR/win32" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -I"$TCC_PATCH_DIR/win32/include" -o builtin.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-win32-tcc" -c "$TCC_PATCH_DIR/lib/alloca.S" -B"$TCC_TRUNK_DIR/win32" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -I"$TCC_PATCH_DIR/win32/include" -o alloca.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-win32-tcc" -c "$TCC_PATCH_DIR/lib/alloca-bt.S" -B"$TCC_TRUNK_DIR/win32" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -I"$TCC_PATCH_DIR/win32/include" -o alloca-bt.o

# Windows-specific files
verbose_do "$TCC_HOST_BIN_DIR/x86_64-win32-tcc" -c "$TCC_PATCH_DIR/win32/lib/chkstk.S" -B"$TCC_TRUNK_DIR/win32" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -I"$TCC_PATCH_DIR/win32/include" -o chkstk.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-win32-tcc" -c "$TCC_PATCH_DIR/win32/lib/crt1.c" -B"$TCC_TRUNK_DIR/win32" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -I"$TCC_PATCH_DIR/win32/include" -o crt1.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-win32-tcc" -c "$TCC_PATCH_DIR/win32/lib/crt1w.c" -B"$TCC_TRUNK_DIR/win32" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -I"$TCC_PATCH_DIR/win32/include" -o crt1w.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-win32-tcc" -c "$TCC_PATCH_DIR/win32/lib/wincrt1.c" -B"$TCC_TRUNK_DIR/win32" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -I"$TCC_PATCH_DIR/win32/include" -o wincrt1.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-win32-tcc" -c "$TCC_PATCH_DIR/win32/lib/wincrt1w.c" -B"$TCC_TRUNK_DIR/win32" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -I"$TCC_PATCH_DIR/win32/include" -o wincrt1w.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-win32-tcc" -c "$TCC_PATCH_DIR/win32/lib/dllcrt1.c" -B"$TCC_TRUNK_DIR/win32" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -I"$TCC_PATCH_DIR/win32/include" -o dllcrt1.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-win32-tcc" -c "$TCC_PATCH_DIR/win32/lib/dllmain.c" -B"$TCC_TRUNK_DIR/win32" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -I"$TCC_PATCH_DIR/win32/include" -o dllmain.o

# Support files for Windows (standalone .o files in lib/)
verbose_do "$TCC_HOST_BIN_DIR/x86_64-win32-tcc" -c "$TCC_PATCH_DIR/lib/runmain.c" -B"$TCC_TRUNK_DIR/win32" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -I"$TCC_PATCH_DIR/win32/include" -o lib/runmain.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-win32-tcc" -c "$TCC_PATCH_DIR/lib/bt-exe.c" -B"$TCC_TRUNK_DIR/win32" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -I"$TCC_PATCH_DIR/win32/include" -o lib/bt-exe.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-win32-tcc" -c "$TCC_PATCH_DIR/lib/bt-log.c" -B"$TCC_TRUNK_DIR/win32" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -I"$TCC_PATCH_DIR/win32/include" -o lib/bt-log.o
verbose_do "$TCC_HOST_BIN_DIR/x86_64-win32-tcc" -c "$TCC_PATCH_DIR/lib/bcheck.c" -B"$TCC_TRUNK_DIR/win32" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -I"$TCC_PATCH_DIR/win32/include" -bt -o lib/bcheck.o
if [ -f "$TCC_PATCH_DIR/lib/bt-dll.c" ]; then
  verbose_do "$TCC_HOST_BIN_DIR/x86_64-win32-tcc" -c "$TCC_PATCH_DIR/lib/bt-dll.c" -B"$TCC_TRUNK_DIR/win32" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -I"$TCC_PATCH_DIR/win32/include" -o lib/bt-dll.o
fi

# Build tcov.c for Windows (included in Windows libtcc1.a)
if [ -f "$TCC_PATCH_DIR/lib/tcov.c" ]; then
  verbose_do "$TCC_HOST_BIN_DIR/x86_64-win32-tcc" -c "$TCC_PATCH_DIR/lib/tcov.c" -B"$TCC_TRUNK_DIR/win32" -Iinclude -I"$TCC_PATCH_DIR" -I"$TCC_PATCH_DIR/include" -I"$TCC_PATCH_DIR/win32/include" -o tcov.o
fi

# Create libtcc1.a for Windows (unprefixed - for embedded use)
echo "Creating libtcc1.a for Windows..."
if [ -f "tcov.o" ]; then
  verbose_do ar rcs lib/libtcc1.a libtcc1.o stdatomic.o atomic.o builtin.o alloca.o alloca-bt.o tcov.o chkstk.o crt1.o crt1w.o wincrt1.o wincrt1w.o dllcrt1.o dllmain.o
else
  verbose_do ar rcs lib/libtcc1.a libtcc1.o stdatomic.o atomic.o builtin.o alloca.o alloca-bt.o chkstk.o crt1.o crt1w.o wincrt1.o wincrt1w.o dllcrt1.o dllmain.o
fi

# Remove the config
if [ -f "$TCC_PATCH_DIR/config.h" ]; then
  verbose_do rm "$TCC_PATCH_DIR/config.h"
fi

echo "============================="
echo "Build completed successfully "
echo "============================="

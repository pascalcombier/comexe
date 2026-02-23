#!/bin/sh

# Stop on errors
set -e

#==============================================================================#
# CONFIGURATION                                                                #
#==============================================================================#

# check tools and stop if missing
gcc -v
x86_64-w64-mingw32-gcc -v

MUSL_LIB_DIR=/usr/lib/x86_64-linux-musl
if [ ! -d "$MUSL_LIB_DIR" ]; then
  echo "ERROR: Missing directory $MUSL_LIB_DIR"
  exit 1
fi

MUSL_INCLUDE_DIR=/usr/include/x86_64-linux-musl
if [ ! -d "$MUSL_INCLUDE_DIR" ]; then
  echo "ERROR: Missing directory $MUSL_INCLUDE_DIR"
  exit 1
fi

MULTI=-j16
DEPS="zlib mimalloc lua libffi libuv luv luasocket mbedtls lua-mbedtls-comexe"

BuildDeps()
{
  MAKEFILE_PARAM="$1"
  shift
  for Dependency in $DEPS; do
    make --no-builtin-rules -C "third-party/src/$Dependency" -f "$MAKEFILE_PARAM" "$@"
  done
}

#==============================================================================#
# CLEANUP                                                                      #
#==============================================================================#

mkdir -p bin

TARGETS_DIR=runtime/comexe/usr/bin/comexe-targets
rm -f "$TARGETS_DIR"/*

#==============================================================================#
# TCC (SPECIAL DEPENDANCY)                                                     #
#==============================================================================#

echo "=== STEP 1 TCC WINDOWS/LINUX ==="

# Cross compile TCC for windows and linux
(cd third-party/src/tcc-vio && ./bootstrap-on-linux.sh)

# Populate runtime libs used by final package
RUNTIME_LIB_DIR=runtime/comexe/usr/lib
RUNTIME_INCLUDE_DIR=runtime/comexe/usr/include
TCC_RUNTIME_LINUX=third-party/src/tcc-vio/bin/tcc-x86-64-linux-runtime
TCC_RUNTIME_WINDOWS=third-party/src/tcc-vio/bin/tcc-x86-64-windows-runtime

if [ ! -d "$TCC_RUNTIME_LINUX" ]; then
  echo "ERROR: Missing directory $TCC_RUNTIME_LINUX"
  exit 1
fi

if [ ! -d "$TCC_RUNTIME_WINDOWS" ]; then
  echo "ERROR: Missing directory $TCC_RUNTIME_WINDOWS"
  exit 1
fi

mkdir -p "$RUNTIME_LIB_DIR"
rm -rf "$RUNTIME_LIB_DIR"/*

cp -R "$MUSL_LIB_DIR" "$RUNTIME_LIB_DIR/"
cp -R "$TCC_RUNTIME_LINUX" "$RUNTIME_LIB_DIR/"
cp -R "$TCC_RUNTIME_WINDOWS" "$RUNTIME_LIB_DIR/"

mkdir -p "$RUNTIME_INCLUDE_DIR"
rm -rf "$RUNTIME_INCLUDE_DIR"/x86_64-linux-musl
cp -R "$MUSL_INCLUDE_DIR" "$RUNTIME_INCLUDE_DIR/"

#==============================================================================#
# BUILD TOOLS                                                                  #
#==============================================================================#

echo "=== STEP 2 BUILD TOOLS ==="

# 1) Build lua and copy into tools
make --no-builtin-rules -C third-party/src/lua -f makefile-l-linux clean
make --no-builtin-rules -C third-party/src/lua -f makefile-l-linux CC="gcc" $MULTI
mkdir -p tools/bin
cp third-party/src/lua/bin/lua55 tools/bin/lua55

# 2) Generate makefiles
tools/bin/lua55 tools/lua/generate-makefile.lua third-party/src/lua/makefile.lua
tools/bin/lua55 tools/lua/generate-makefile.lua third-party/src/zlib/makefile.lua
tools/bin/lua55 tools/lua/generate-makefile.lua third-party/src/mimalloc/makefile.lua
tools/bin/lua55 tools/lua/generate-makefile.lua third-party/src/libffi/makefile.lua
tools/bin/lua55 tools/lua/generate-makefile.lua third-party/src/libuv/makefile.lua
tools/bin/lua55 tools/lua/generate-makefile.lua third-party/src/luv/makefile.lua
tools/bin/lua55 tools/lua/generate-makefile.lua third-party/src/luasocket/makefile.lua
tools/bin/lua55 tools/lua/generate-makefile.lua third-party/src/mbedtls/makefile.lua
tools/bin/lua55 tools/lua/generate-makefile.lua third-party/src/lua-mbedtls-comexe/makefile.lua

# 3) Build zlib for trivial-minizip
make --no-builtin-rules -C third-party/src/zlib -f makefile-l-linux clean
make --no-builtin-rules -C third-party/src/zlib -f makefile-l-linux CC="gcc" $MULTI

# 4) Build minizip/makeheaders tools
make --no-builtin-rules -C tools -f makefile-l-linux clean
make --no-builtin-rules -C tools -f makefile-l-linux CC="gcc" $MULTI

#==============================================================================#
# BUILD DEPS AND APP LINUX                                                     #
#==============================================================================#

echo "=== STEP 3 BUILD DEPS AND APP LINUX X86-64 ==="

# Linux dependencies
BuildDeps makefile-l-linux clean
CC="gcc" BuildDeps makefile-l-linux $MULTI

# Build Linux app
make -f makefile-l-linux clean
make -f makefile-l-linux all CC="gcc" $MULTI

# Save targets
cp bin/comexe     "$TARGETS_DIR/x86_64-linux-con"
cp bin/comexe-dbg "$TARGETS_DIR/x86_64-linux-dbg"
chmod +x "$TARGETS_DIR/x86_64-linux-con"
chmod +x "$TARGETS_DIR/x86_64-linux-dbg"

# Clean build
make -f makefile-l-linux clean

#==============================================================================#
# BUILD DEPS AND APP WINDOWS                                                   #
#==============================================================================#

echo "=== STEP 4 BUILD DEPS AND APP WINDOWS X86-64 ==="

# Build Windows dependencies
BuildDeps makefile-l-mingw clean
rm -f third-party/src/lua/bin/*.o third-party/src/lua/bin/liblua.a
CC="x86_64-w64-mingw32-gcc" AR="x86_64-w64-mingw32-ar" BuildDeps makefile-l-mingw $MULTI

# Build Windows app
make -f makefile-l-mingw clean
make -f makefile-l-mingw all $MULTI CC="x86_64-w64-mingw32-gcc" AR="x86_64-w64-mingw32-ar" WINDRES="x86_64-w64-mingw32-windres" STRIP="x86_64-w64-mingw32-strip"

# Save targets
cp bin/comexe-con.exe "$TARGETS_DIR/x86_64-windows-con.exe"
cp bin/comexe-dbg.exe "$TARGETS_DIR/x86_64-windows-dbg.exe"
cp bin/comexe-gui.exe "$TARGETS_DIR/x86_64-windows-gui.exe"

#==============================================================================#
# PACKAGING                                                                    #
#==============================================================================#

echo "=== STEP 5 PACKAGING ==="

# Create and clean distribution directory
mkdir -p dist

# At this stage, dist might contains dist/tmp which is a directory
rm -rf dist/*

ZIP_RUNTIME="bin/lua55ce-runtime.zip"
rm -f $ZIP_RUNTIME

tools/bin/trivial-minizip -o $ZIP_RUNTIME runtime src-lua55ce 9

cat "$TARGETS_DIR/x86_64-linux-con"       $ZIP_RUNTIME > dist/lua55ce-x86_64-linux
cat "$TARGETS_DIR/x86_64-linux-dbg"       $ZIP_RUNTIME > dist/lua55ced-x86_64-linux
cat "$TARGETS_DIR/x86_64-windows-con.exe" $ZIP_RUNTIME > dist/lua55ce-x86_64-windows.exe
cat "$TARGETS_DIR/x86_64-windows-dbg.exe" $ZIP_RUNTIME > dist/lua55ced-x86_64-windows.exe

chmod +x dist/lua55ce-x86_64-linux
chmod +x dist/lua55ced-x86_64-linux

# Create distribution packages (linux)
mkdir -p dist/tmp
cp dist/lua55ce-x86_64-linux  dist/tmp/lua55ce
cp dist/lua55ced-x86_64-linux dist/tmp/lua55ced
chmod +x dist/tmp/lua55ce
chmod +x dist/tmp/lua55ced
(cd dist/tmp && zip -9 ../lua55ce-x86_64-linux.zip lua55ce lua55ced)
rm -f dist/tmp/*

# Create distribution packages (windows)
cp dist/lua55ce-x86_64-windows.exe  dist/tmp/lua55ce.exe
cp dist/lua55ced-x86_64-windows.exe dist/tmp/lua55ced.exe
(cd dist/tmp && zip -9 ../lua55ce-x86_64-windows.zip lua55ce.exe lua55ced.exe)
rm -rf dist/tmp

# Clean bin folder from packaged files
rm -f $ZIP_RUNTIME
rm -f bin/lua55ce-x86_64-*
rm -f bin/lua55ced-x86_64-*
rm -f bin/lua55ce
rm -f bin/lua55ced
rm -f bin/lua55ce.exe
rm -f bin/lua55ced.exe

echo "=== TARGETS"
ls "$TARGETS_DIR" -lha
echo "=== DIST"
ls dist/ -lha

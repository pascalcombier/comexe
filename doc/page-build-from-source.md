# Building ComEXE from source

* [Introduction](#introduction)
* [Requirements](#requirements)
* [Build on Windows](#build-on-windows)
* [Build on Linux](#build-on-linux)
* [Output](#output)
* [Update the makefiles](#update-the-makefiles)
* [Run the regression tests](#run-the-regression-tests)

## Introduction

ComEXE can be built on Windows and Linux. The build system uses Zig to cross-compile every supported target.

Requirements:

* [GNU Make](https://www.gnu.org/software/make/)
* [Zig 0.16.0](https://ziglang.org)

## Build on Windows

```sh
make -f makefile-x86_64-windows-gnu -j8
```

## Build on Linux

```sh
make -f makefile-x86_64-linux-gnu -j8
```

## Output

```
bin/dist/lua55ce.zip
```

## Update the makefiles

### Check the index

```sh
lua55ce tools/lua/make-generate.lua build.lua --check-index
```

### Update the index

```sh
lua55ce tools/lua/make-generate.lua build.lua --build-index
```

### Generate the makefiles on the current host

```sh
lua55ce tools/lua/make-generate.lua build.lua --output makefile-x86_64-windows-gnu
```

### Generate the makefiles for a target host

```sh
lua55ce tools/lua/make-generate.lua build.lua --host x86_64-linux-gnu --output makefile-x86_64-linux-gnu
```

## Run the regression tests

```sh
lua55ce tests/runner.lua --fast
```

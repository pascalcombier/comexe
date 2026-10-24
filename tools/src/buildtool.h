/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME tools/src/buildtool.h                                             *
 * CONTENT  Special build-time tool to help build ComEXE (ZIP, concat, etc)   *
 *----------------------------------------------------------------------------*
 * Copyright (c) 2020-2026 Pascal COMBIER                                     *
 * This source code is licensed under the MIT license (see the LICENSE file). *
 * SPDX-License-Identifier: MIT                                               *
 *----------------------------------------------------------------------------*
 *
 * This file is to document the build-time helper bin/tools/buildtool.exe
 *
 * lua55ce is not easy to bootstrap. We need to concatenate an EXE and a ZIP
 * file. But on Windows, user typically don't have utility like zip. One role of
 * buildtool.exe is to provide such zip feature.
 *
 * For ZIP feature, we implement a Lua interpreter with minizip-ng (and
 * luv). Original lua.c source code is designed to make it easy to build Lua
 * interpreters with custom libraries. See "#if !defined(luai_openlibs)" in
 * lua.c. We essentially compile to stock lua interpreter lua.c with an
 * "overlay" with custom libraries.
 *
 * The target is to be minimalist in the approach, we don't want to maintain an
 * alternate half-bakced lua55ce just for the bootstrapping.
 */

#ifndef COMEXE_BUILDTOOL_H
#define COMEXE_BUILDTOOL_H

/* Pre-declaration */
struct lua_State;

void BUILDTOOL_BootLibraries (struct lua_State *LuaState);

#endif

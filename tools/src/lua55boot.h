/*----------------------------------------------------------------------------*
 * PROJECT  ComEXE                                                            *
 * FILENAME lua55boot.h                                                       *
 * CONTENT  Special lua interpreter for make.lua/pack.lua                     *
 *----------------------------------------------------------------------------*
 * Copyright (c) 2020-2026 Pascal COMBIER                                     *
 * This source code is licensed under the BSD 2-clause license found in the   *
 * LICENSE file in the root directory of this source tree.                    *
 *----------------------------------------------------------------------------*
 *
 * This file is to bootstrap a Lua interpreter with some features for make.lua
 * and pack.lua.
 *
 * In order to create lua55ce we need a way to to create ZIP files. Then we put
 * the Lua runtime files into a ZIP and we concatenate the lua55-XX-con with the
 * runtime ZIP to generate the final program.
 *
 * To solve the chicken-and-egg issue, we unfortunately cannot use lua55ce to
 * implement make.lua and pack.lua. So we generate a build-time Lua specific
 * interpreter with a couple of features:
 * - newpathname
 * - luv
 * - minizip-ng
 *
 * lua.c interpreter source code is designed to support those kind of things,
 * see "#if !defined(luai_openlibs)" in lua.c. We essentially compile to stock
 * lua interpreter lua.c with an "overlay" with custom libraries.
 *
 * We also embed the Lua runtime directly in the lua55-init.c (actually a subset
 * of init.lua from lua55ce). For that we use ZIG's #embed (we could have use
 * incbin as well).
 *
 * The target is to be minimalist in the approach, we don't want to maintain an
 * alternate half-bakced lua55ce just for the bootstrapping.
 *
 * WEIRD: it's built in lua.lua and NOT tools.lua because it's easier.
 */

#ifndef COMEXE_LUA55BOOT_H
#define COMEXE_LUA55BOOT_H

/* Pre-declaration */
struct lua_State;

void LUA_BootOpenLibraries (struct lua_State *LuaState);

#define luai_openlibs(LuaState) LUA_BootOpenLibraries(LuaState)

#endif

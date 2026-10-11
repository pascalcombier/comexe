--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- lua55ce-runtime.zip

--------------------------------------------------------------------------------
-- MANIFEST                                                                   --
--------------------------------------------------------------------------------

local Entries = {
  -- Trees
  { Tree = "runtime/comexe", Prefix = "comexe" },
  { Tree = "src-lua55ce",    Prefix = ""       },
  -- The files in bin/ cannot be dynamically listed because the files does not exist yet
  -- So to make simple: just list the files manually
  -- Files
  { File = "bin/x86_64-windows-gnu/src/comexe-con.exe", Entry = "comexe/usr/bin/comexe-targets/x86_64-windows-con.exe" },
  { File = "bin/x86_64-windows-gnu/src/comexe-dbg.exe", Entry = "comexe/usr/bin/comexe-targets/x86_64-windows-dbg.exe" },
  { File = "bin/x86_64-windows-gnu/src/comexe-gui.exe", Entry = "comexe/usr/bin/comexe-targets/x86_64-windows-gui.exe" },
  { File = "bin/x86_64-linux-musl/src/comexe",          Entry = "comexe/usr/bin/comexe-targets/x86_64-linux-con"       },
  { File = "bin/x86_64-linux-musl/src/comexe-dbg",      Entry = "comexe/usr/bin/comexe-targets/x86_64-linux-dbg"       },
  { File = "bin/x86_64-linux-gnu/src/comexe-dyn",       Entry = "comexe/usr/bin/comexe-targets/x86_64-linux-con-dyn"   },
  { File = "bin/x86_64-linux-gnu/src/comexe-dbg-dyn",   Entry = "comexe/usr/bin/comexe-targets/x86_64-linux-dbg-dyn"   },
  -- Tcc headers
  { Tree = "third-party/src/tcc-vio/src/include",       Prefix = "comexe/usr/lib/tcc-x86-64-windows-runtime/include"   },
  { Tree = "third-party/src/tcc-vio/src/win32/include", Prefix = "comexe/usr/lib/tcc-x86-64-windows-runtime/include"   },
  -- Tcc sources
  { File = "third-party/src/tcc-vio/src/include/tccdefs.h",      Entry = "comexe/usr/lib/tcc-x86-64-linux-runtime/include/tccdefs.h"    },
  { File = "third-party/src/tcc-vio/src/win32/lib/gdi32.def",    Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/lib/gdi32.def"      },
  { File = "third-party/src/tcc-vio/src/win32/lib/kernel32.def", Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/lib/kernel32.def"   },
  { File = "third-party/src/tcc-vio/src/win32/lib/msvcrt.def",   Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/lib/msvcrt.def"     },
  { File = "third-party/src/tcc-vio/src/win32/lib/user32.def",   Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/lib/user32.def"     },
  { File = "third-party/src/tcc-vio/src/win32/lib/ws2_32.def",   Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/lib/ws2_32.def"     },
  -- Tcc generated runtime headers and archives
  { File = "bin/tcc-vio/runtime-linux/include/tccdefs_.h",       Entry = "comexe/usr/lib/tcc-x86-64-linux-runtime/include/tccdefs_.h"   },
  { File = "bin/tcc-vio/runtime-windows/include/tccdefs_.h",     Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/include/tccdefs_.h" },
  { File = "bin/tcc-vio/runtime-linux/libtcc1.a",                Entry = "comexe/usr/lib/tcc-x86-64-linux-runtime/libtcc1.a"            },
  { File = "bin/tcc-vio/runtime-windows/lib/libtcc1.a",          Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/lib/libtcc1.a"      },
  -- Tcc generated linux runtime objects
  { File = "bin/tcc-vio/runtime-linux/alloca.o",                 Entry = "comexe/usr/lib/tcc-x86-64-linux-runtime/alloca.o"             },
  { File = "bin/tcc-vio/runtime-linux/alloca-bt.o",              Entry = "comexe/usr/lib/tcc-x86-64-linux-runtime/alloca-bt.o"          },
  { File = "bin/tcc-vio/runtime-linux/atomic.o",                 Entry = "comexe/usr/lib/tcc-x86-64-linux-runtime/atomic.o"             },
  { File = "bin/tcc-vio/runtime-linux/bcheck.o",                 Entry = "comexe/usr/lib/tcc-x86-64-linux-runtime/bcheck.o"             },
  { File = "bin/tcc-vio/runtime-linux/bt-exe.o",                 Entry = "comexe/usr/lib/tcc-x86-64-linux-runtime/bt-exe.o"             },
  { File = "bin/tcc-vio/runtime-linux/bt-log.o",                 Entry = "comexe/usr/lib/tcc-x86-64-linux-runtime/bt-log.o"             },
  { File = "bin/tcc-vio/runtime-linux/builtin.o",                Entry = "comexe/usr/lib/tcc-x86-64-linux-runtime/builtin.o"            },
  { File = "bin/tcc-vio/runtime-linux/dsohandle.o",              Entry = "comexe/usr/lib/tcc-x86-64-linux-runtime/dsohandle.o"          },
  { File = "bin/tcc-vio/runtime-linux/libtcc1.o",                Entry = "comexe/usr/lib/tcc-x86-64-linux-runtime/libtcc1.o"            },
  { File = "bin/tcc-vio/runtime-linux/runmain.o",                Entry = "comexe/usr/lib/tcc-x86-64-linux-runtime/runmain.o"            },
  { File = "bin/tcc-vio/runtime-linux/stdatomic.o",              Entry = "comexe/usr/lib/tcc-x86-64-linux-runtime/stdatomic.o"          },
  { File = "bin/tcc-vio/runtime-linux/tcov.o",                   Entry = "comexe/usr/lib/tcc-x86-64-linux-runtime/tcov.o"               },
  -- Tcc generated windows runtime objects
  { File = "bin/tcc-vio/runtime-windows/alloca.o",               Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/alloca.o"           },
  { File = "bin/tcc-vio/runtime-windows/alloca-bt.o",            Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/alloca-bt.o"        },
  { File = "bin/tcc-vio/runtime-windows/atomic-clang.o",         Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/atomic-clang.o"     },
  { File = "bin/tcc-vio/runtime-windows/builtin.o",              Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/builtin.o"          },
  { File = "bin/tcc-vio/runtime-windows/chkstk.o",               Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/chkstk.o"           },
  { File = "bin/tcc-vio/runtime-windows/crt1.o",                 Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/crt1.o"             },
  { File = "bin/tcc-vio/runtime-windows/crt1w.o",                Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/crt1w.o"            },
  { File = "bin/tcc-vio/runtime-windows/dllcrt1.o",              Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/dllcrt1.o"          },
  { File = "bin/tcc-vio/runtime-windows/dllmain.o",              Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/dllmain.o"          },
  { File = "bin/tcc-vio/runtime-windows/dsohandle.o",            Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/dsohandle.o"        },
  { File = "bin/tcc-vio/runtime-windows/libtcc1.o",              Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/libtcc1.o"          },
  { File = "bin/tcc-vio/runtime-windows/stdatomic.o",            Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/stdatomic.o"        },
  { File = "bin/tcc-vio/runtime-windows/tcov.o",                 Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/tcov.o"             },
  { File = "bin/tcc-vio/runtime-windows/wincrt1.o",              Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/wincrt1.o"          },
  { File = "bin/tcc-vio/runtime-windows/wincrt1w.o",             Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/wincrt1w.o"         },
  -- Tcc generated windows runtime support objects
  { File = "bin/tcc-vio/runtime-windows/lib/bcheck.o",           Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/lib/bcheck.o"       },
  { File = "bin/tcc-vio/runtime-windows/lib/bt-exe.o",           Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/lib/bt-exe.o"       },
  { File = "bin/tcc-vio/runtime-windows/lib/bt-log.o",           Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/lib/bt-log.o"       },
  { File = "bin/tcc-vio/runtime-windows/lib/runmain.o",          Entry = "comexe/usr/lib/tcc-x86-64-windows-runtime/lib/runmain.o"      },
}

return Entries

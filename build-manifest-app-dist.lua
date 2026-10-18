--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- build bin/dist/lua55ce.zip from build-index.lua

--------------------------------------------------------------------------------
-- MANIFEST                                                                   --
--------------------------------------------------------------------------------

local Entries = {
  -- Files
  { File = "bin/x86_64-windows-gnu/src/lua55ce.exe", Entry = "lua55ce-x86_64-windows.exe" },
  { File = "bin/x86_64-linux-musl/src/lua55ce",      Entry = "lua55ce-x86_64-linux"       },
  { File = "bin/x86_64-linux-gnu/src/lua55ce-dyn",   Entry = "lua55ce-x86_64-linux-dyn"   },
  { File = "bin/x86_64-windows-gnu/src/libtcc.dll",  Entry = "libtcc.dll"                 },
  { File = "bin/x86_64-linux-gnu/src/libtcc.so",     Entry = "libtcc.so"                  },
  { File = "LICENSE",                                Entry = "LICENSE"                    },
  -- Directory
  { Tree = "doc", Prefix = "doc" },
}

return Entries


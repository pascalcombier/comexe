--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- bin/dist/lua55ce-<version>-linux-x86_64.zip

--------------------------------------------------------------------------------
-- MANIFEST                                                                   --
--------------------------------------------------------------------------------

local Entries = {
  -- Files
  { File = "bin/x86_64-linux-musl/src/lua55ce-musl", Entry = "lua55ce-musl" },
  { File = "bin/x86_64-linux-gnu/src/lua55ce-gnu",   Entry = "lua55ce-gnu"  },
  { File = "bin/x86_64-linux-gnu/src/libtcc.so",     Entry = "libtcc.so"    },
  { File = "bin/x86_64-windows-gnu/src/libtcc.dll",  Entry = "libtcc.dll"   },
  { File = "LICENSE",                                Entry = "LICENSE"      },
  -- Directory
  { Tree = "doc", Prefix = "doc" },
}

return Entries

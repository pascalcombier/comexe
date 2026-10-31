--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- bin/dist/lua55ce-<version>-windows-x86_64.zip

--------------------------------------------------------------------------------
-- MANIFEST                                                                   --
--------------------------------------------------------------------------------

local Entries = {
  -- Files
  { File = "bin/x86_64-windows-gnu/src/lua55ce.exe", Entry = "lua55ce.exe" },
  { File = "bin/x86_64-windows-gnu/src/libtcc.dll",  Entry = "libtcc.dll"  },
  { File = "bin/x86_64-linux-gnu/src/libtcc.so",     Entry = "libtcc.so"   },
  { File = "LICENSE",                                Entry = "LICENSE"     },
  -- Directory
  { Tree = "doc", Prefix = "doc" },
}

return Entries

--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- libraries
-- makeheaders
-- lua
-- minizip-ng
-- comexe.h
-- application
-- lua55ce-runtime.zip
-- dist

--------------------------------------------------------------------------------
-- BUILD DESCRIPTION                                                          --
--------------------------------------------------------------------------------

local RootDescription = {
  -- Build for all those targets
  Triples = {
    "x86_64-windows-gnu",
    "x86_64-linux-musl",
    "x86_64-linux-gnu",
  },
  -- Prevent zig from using "smart" output
  Environment = {
    NO_COLOR = "1",
  },
  -- Manual directory removal
  CleanDirs = {
    "bin/$TRIPLE",
    "bin/tools",
    "bin/$TRIPLE/src",
    "bin/app",
    "bin/dist",
  },
  -- Keep the manual index build-index.lua
  MonitoredDirs = {
    -- prerequisites for lua55ce-runtime.zip
    { "runtime", "runtime/comexe"                            },
    { "runtime", "src-lua55ce"                               },
    { "tccvio",  "third-party/src/tcc-vio/src/include"       },
    { "tccvio",  "third-party/src/tcc-vio/src/win32/include" },
    -- prerequisites for bin/dist/lua55ce.zip
    { "doc", "doc" },
  },
  -- Components
  Components = {
    { "ALL",  "third-party/src/zlib/zlib.lua"                             },
    { "ALL",  "third-party/src/minizip-ng/minizip-ng.lua"                 },
    { "ALL",  "third-party/src/mimalloc/mimalloc.lua"                     },
    { "ALL",  "third-party/src/lua/lua.lua"                               },
    { "ALL",  "third-party/src/libffi/libffi.lua"                         },
    { "ALL",  "third-party/src/libuv/libuv.lua"                           },
    { "ALL",  "third-party/src/luv/luv.lua"                               },
    { "ALL",  "third-party/src/luasocket/luasocket.lua"                   },
    { "ALL",  "third-party/src/mbedtls/mbedtls.lua"                       },
    { "ALL",  "third-party/src/lua-mbedtls-comexe/lua-mbedtls-comexe.lua" },
    { "ALL",  "third-party/src/lpeg/lpeg.lua"                             },
    { "HOST", "third-party/src/tcc-vio/tcc.lua"                           },
    { "HOST", "tools/tools.lua"                                           },
    { "HOST", "src/build-comexe-header.lua"                               },
    { "ALL",  "src/build-app.lua"                                         },
    { "HOST", "src/build-runtime.lua"                                     },
    { "HOST", "src/build-dist.lua"                                        },
  },
}

return RootDescription

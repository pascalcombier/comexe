--------------------------------------------------------------------------------
-- DOCUMENTATION                                                              --
--------------------------------------------------------------------------------

-- This file provide an API which is compatible with LuaSec, it basically allow
-- to use the example of LuaSec as documented in LuaSec documentation, but it
-- will use mbedtls-lua instead of OpenSSL.
--
-- Obviously, this file might conflict if one want to use original LuaSec
-- implementation with OpenSSL instead. In that case, one might just delete this
-- ssl.lua
--

--------------------------------------------------------------------------------
-- EXAMPLE OF USE                                                             --
--------------------------------------------------------------------------------

-- require("socket") -- LuaSocket
-- require("ssl")    -- This file
-- 
-- -- TLS/SSL client parameters (omitted)
-- local params
--  
-- local conn = socket.tcp()
-- conn:connect("127.0.0.1", 8888)
--  
-- -- TLS/SSL initialization
-- conn = ssl.wrap(conn, params)
-- conn:dohandshake()
-- --
-- print(conn:receive("*l"))
-- conn:close()

--------------------------------------------------------------------------------
-- EXAMPLE OF USE                                                             --
--------------------------------------------------------------------------------

local Module = require("com.ssl")

return Module

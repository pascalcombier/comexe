-- Just check if the socket.lua is available from the ZIP file
-- Setting "loader-configuration" with embeded dependancies "D"

local Socket = require("socket")
assert(Socket, "Socket could not be loaded")

local Server, ErrorMessage = Socket.bind("127.0.0.1", 12345)
assert((ErrorMessage == nil), ErrorMessage)

Server:close()

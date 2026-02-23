-- https://github.com/neoxic/lua-mbedtls

local socket  = require 'socket'
local mbedtls = require 'mbedtls'
local ssl     = require 'mbedtls.ssl'

local function read(h, n)
  return assert(h:receive(n))
end

local function write(h, s)
  return assert(h:send(s))
end

local tcp = assert(socket.connect('github.com', 443))
local cfg = ssl.newconfig('tls-client')
local ctx = ssl.newcontext(cfg, read, write, tcp)

ctx:write('GET / HTTP/1.0\r\n\r\n')
print(ctx:read(9999))

ctx:reset()
tcp:close()

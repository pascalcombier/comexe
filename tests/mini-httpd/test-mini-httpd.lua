--------------------------------------------------------------------------------
-- IMPORTS                                                                    --
--------------------------------------------------------------------------------

local Runtime    = require("com.runtime")
local MiniHttpd  = require("com.mini-httpd")
local HelloHttpd = require("hello-httpd")

local format = string.format

--------------------------------------------------------------------------------
-- RESOURCES                                                                  --
--------------------------------------------------------------------------------

local CertKeyFile = Runtime.getrelativepath("127.0.0.1+1-certkey.pem")
local Cert        = Runtime.loadresource("127.0.0.1+1.pem")
local Key         = Runtime.loadresource("127.0.0.1+1-key.pem")

assert(Cert,        "Missing CERT file")
assert(Key,         "Missing  KEY file")
assert(CertKeyFile, "Missing file")

--------------------------------------------------------------------------------
-- MAIN: TEST FUNCTION                                                        --
--------------------------------------------------------------------------------

-- Configuration for plain HTTP
local ConfigurationPlain = {
  host = "127.0.0.1",
  port = 8801,
}

-- Configuration for SSL with file
local ConfigurationSslFile = {
  host        = "127.0.0.1",
  port        = 8802,
  certkeyfile = CertKeyFile,
}

-- Configuration for SSL with memory
local ConfigurationSslMemory = {
  host = "127.0.0.1",
  port = 8803,
  cert = Cert,
  key  = Key,
}

-- Create the main server
local MainHttpServer = MiniHttpd.newserver()

-- Create HTTP applications
local AppPlain     = HelloHttpd.newserverapp(MainHttpServer)
local AppSslFile   = HelloHttpd.newserverapp(MainHttpServer)
local AppSslMemory = HelloHttpd.newserverapp(MainHttpServer)

-- Bind HTTP handlers
MainHttpServer:bind(ConfigurationPlain,     AppPlain)
MainHttpServer:bind(ConfigurationSslFile,   AppSslFile)
MainHttpServer:bind(ConfigurationSslMemory, AppSslMemory)

-- Start listening
local Success, ErrorMessage

Success, ErrorMessage = MainHttpServer:listen(AppPlain)
assert(Success, format("test-plain failed: %s", ErrorMessage))

Success, ErrorMessage = MainHttpServer:listen(AppSslFile)
assert(Success, format("test-ssl-file failed: %s", ErrorMessage))

Success, ErrorMessage = MainHttpServer:listen(AppSslMemory)
assert(Success, format("test-ssl-mem failed: %s", ErrorMessage))

-- Run the event loop
MainHttpServer:runloop()
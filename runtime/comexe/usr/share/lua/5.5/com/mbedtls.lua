--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

-- Message digests (streaming, usable for large files).
-- File I/O uses luv, so UTF-8 paths work on Windows.

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local RawMbedtls = require("com.raw.mbedtls")
local uv         = require("luv")

local format = string.format
local concat = table.concat
local append = table.insert
local byte   = string.byte
local open   = uv.fs_open
local read   = uv.fs_read
local close  = uv.fs_close

local md_info_from_string = RawMbedtls.md_info_from_string
local md_size             = RawMbedtls.md_size
local md_new              = RawMbedtls.md_new
local md_free             = RawMbedtls.md_free
local md_setup            = RawMbedtls.md_setup
local md_starts           = RawMbedtls.md_starts
local md_update           = RawMbedtls.md_update
local md_finish           = RawMbedtls.md_finish
local md_algorithms       = RawMbedtls.md_algorithms

local DEFAULT_ALGORITHM     = "SHA256"
local DEFAULT_CHUNK_SIZE    = 65536
local FILE_READ_MODE        = "r"
local FILE_READ_PERMISSIONS = tonumber("0666", 8)

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function ToHex (Data)
  local Parts       = {}
  local SizeInBytes = #Data
  for Index = 1, SizeInBytes do
    local ByteHexString = format("%02x", byte(Data, Index))
    append(Parts, ByteHexString)
  end
  return concat(Parts)
end

-- return nil if no error
local function FormatErrorString (ReturnCode, FunctionName)
  local ErrorString
  if (ReturnCode ~= 0) then
    ErrorString = format("mbedtls_%s failed (error %d)", FunctionName, ReturnCode)
  end
  return ErrorString
end

--------------------------------------------------------------------------------
-- DIGESTER OBJECT                                                            --
--------------------------------------------------------------------------------

local function DIGEST_MethodUpdate (Digester, Data)
  local Context = Digester.Context
  assert(Context, "digester already finalized")
  local ErrorString = FormatErrorString(md_update(Context, Data), "md_update")
  return ErrorString
end

local function DIGEST_MethodDigest (Digester, OptionalFormat)
  local Format  = (OptionalFormat or "raw")
  local Context = Digester.Context
  local Result
  local ErrorString
  -- Validate the format
  assert(Context, "digester already finalized")
  assert(((Format == "raw") or (Format == "hex")), format("invalid digest format %q", OptionalFormat))
  -- Finish and release the context
  local ReturnCode, Digest = md_finish(Context, Digester.DigestSizeInBytes)
  -- Check error
  ErrorString = FormatErrorString(ReturnCode, "md_finish")
  -- Release the context
  md_free(Context)
  Digester.Context = nil
  -- Format the result
  if (not ErrorString) then
    if (Format == "hex") then
      Result = ToHex(Digest)
    else
      Result = Digest
    end
  end
  return Result, ErrorString
end

local function DIGEST_MethodCollectGarbage (DigesterObject)
  local DigesterContext = DigesterObject.Context
  if DigesterContext then
    md_free(DigesterContext)
    DigesterObject.Context = nil
  end
end

local DIGEST_Metatable = {
  -- METATABLE_LuaDefinedMethods
  __gc = DIGEST_MethodCollectGarbage,
  -- METATABLE_UserDefinedMethods
  __index = {
    Update = DIGEST_MethodUpdate,
    Digest = DIGEST_MethodDigest,
  }
}

local function DIGEST_NewDigester (OptionalAlgorithm)
  -- Handle defaults
  local Algorithm = (OptionalAlgorithm or DEFAULT_ALGORITHM)
  -- Info is a static constant in the C side, nothing to release
  local Info = md_info_from_string(Algorithm)
  local NewContext
  local ErrorString
  local NewDigester
  -- Setup and start the digest
  if Info then
    NewContext  = md_new()
    ErrorString = FormatErrorString(md_setup(NewContext, Info), "md_setup")
    if (not ErrorString) then
      ErrorString = FormatErrorString(md_starts(NewContext), "md_starts")
    end
    if ErrorString then
      md_free(NewContext)
      NewContext = nil
    end
  else
    ErrorString = format("unsupported digest algorithm '%s'", Algorithm)
  end
  -- If not error at this stage, create the new digester object
  if NewContext then
    NewDigester = {
      Context           = NewContext,
      DigestSizeInBytes = md_size(Info),
    }
    setmetatable(NewDigester, DIGEST_Metatable)
  end
  return NewDigester, ErrorString
end

--------------------------------------------------------------------------------
-- PUBLIC FUNCTIONS                                                           --
--------------------------------------------------------------------------------

local function HashString (Data, OptionalAlgorithm)
  -- Create the digester
  local NewDigester, ErrorString = DIGEST_NewDigester(OptionalAlgorithm)
  assert(NewDigester, ErrorString)
  -- Feed the digester
  ErrorString = NewDigester:Update(Data)
  -- Finalize
  local HexString
  if (not ErrorString) then
    HexString, ErrorString = NewDigester:Digest("hex")
  end
  assert(HexString, ErrorString)
  return HexString
end

local function HashFile (Path, OptionalAlgorithm)
  -- Open file
  local File, OpenErrorString = open(Path, FILE_READ_MODE, FILE_READ_PERMISSIONS)
  assert(File, format("cannot open '%s': %s", Path, OpenErrorString))
  -- Create the digester
  local DigesterObject, ErrorString = DIGEST_NewDigester(OptionalAlgorithm)
  local HexString
  -- Feed the digester chunk by chunk
  if DigesterObject then
    local Offset  = 0
    local Reading = true
    while Reading and (not ErrorString) do
      local Chunk, ReadErrorString = read(File, DEFAULT_CHUNK_SIZE, Offset)
      if Chunk and (#Chunk > 0) then
        ErrorString = DigesterObject:Update(Chunk)
        if (not ErrorString) then
          Offset = (Offset + #Chunk)
        end
      else
        -- At end of file, luv returns an empty string and no error
        Reading = false
        if (Chunk == nil) then
          ErrorString = format("cannot read file: %s", ReadErrorString)
        end
      end
    end
    -- Finalize
    if (not ErrorString) then
      HexString, ErrorString = DigesterObject:Digest("hex")
    end
  end
  -- Cleanup
  close(File)
  -- On error the digester will be released with __gc
  assert(HexString, ErrorString)
  return HexString
end

--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  -- Lowlevel
  algorithms  = md_algorithms,
  newdigester = DIGEST_NewDigester,
  -- High level
  hashstring  = HashString,
  hashfile    = HashFile,
}

return PUBLIC_API

--------------------------------------------------------------------------------
-- DOCUMENTATION                                                              --
--------------------------------------------------------------------------------

-- ChunkBuffer
-- A chunked byte buffer for socket receive operations (for mbedtls API)

--------------------------------------------------------------------------------
-- IMPORTS                                                                    --
--------------------------------------------------------------------------------

local Runtime = require("com.runtime")

local find   = string.find
local sub    = string.sub
local concat = table.concat

local append       = Runtime.append
local hassuffix    = Runtime.hassuffix
local removesuffix = Runtime.removesuffix

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function CHUNK_ResetState (ChunkBuffer)
  -- Reset queue and indices
  ChunkBuffer.Queue          = {}
  ChunkBuffer.FirstIndex     = 1
  ChunkBuffer.TailIndex      = 0
  ChunkBuffer.FirstByteIndex = 1
  ChunkBuffer.SizeInBytes    = 0
end

local function CHUNK_ResetNewlineScanCache (ChunkBuffer)
  -- Reset scan state for newline detection
  ChunkBuffer.ScanIndex  = 1
  ChunkBuffer.ScanOffset = 1
  ChunkBuffer.ScanCount  = 0
end

local function CHUNK_MethodAppend (ChunkBuffer, ChunkString)
  -- Get the size of the chunk
  local SizeInBytes = #ChunkString
  local NewSizeInByte
  if (SizeInBytes > 0) then
    -- Retrieve current state
    local TailIndex   = ChunkBuffer.TailIndex
    local CurrentSize = ChunkBuffer.SizeInBytes
    -- Calculate new index and size
    local NewIndex = (TailIndex + 1)
    NewSizeInByte  = (CurrentSize + SizeInBytes)
    -- Update buffer state
    ChunkBuffer.TailIndex       = NewIndex
    ChunkBuffer.Queue[NewIndex] = ChunkString
    ChunkBuffer.SizeInBytes     = NewSizeInByte
  else
    NewSizeInByte = ChunkBuffer.SizeInBytes
  end
  -- Return value
  return NewSizeInByte
end

local function CHUNK_MethodLen (ChunkBuffer)
  -- Return the total size in bytes
  return ChunkBuffer.SizeInBytes
end

local function CHUNK_MethodConsume (ChunkBuffer, SizeInBytes)
  -- Initialize parts and remaining bytes
  local Parts          = {}
  local RemainingBytes = SizeInBytes
  local TailIndex      = ChunkBuffer.TailIndex
  local Index          = ChunkBuffer.FirstIndex
  local FirstByteIndex = ChunkBuffer.FirstByteIndex
  -- Consume chunks until enough bytes are collected
  while (RemainingBytes > 0) and (Index <= TailIndex) do
    local Chunk      = ChunkBuffer.Queue[Index]
    local ChunkSize  = #Chunk
    local StartIndex = FirstByteIndex
    local Available  = ((ChunkSize - StartIndex) + 1)
    local TakeCount  = Available
    if (TakeCount > RemainingBytes) then
      TakeCount = RemainingBytes
    end
    local Part
    if (StartIndex == 1) and (TakeCount == ChunkSize) then
      Part = Chunk
    else
      Part = sub(Chunk, StartIndex, ((StartIndex + TakeCount) - 1))
    end
    append(Parts, Part)
    RemainingBytes = (RemainingBytes - TakeCount)
    if (TakeCount == Available) then
      Index          = (Index + 1)
      FirstByteIndex = 1
    else
      FirstByteIndex = (StartIndex + TakeCount)
    end
  end
  -- Update buffer state
  if (Index > TailIndex) then
    CHUNK_ResetState(ChunkBuffer)
  else
    ChunkBuffer.FirstIndex     = Index
    ChunkBuffer.FirstByteIndex = FirstByteIndex
    ChunkBuffer.SizeInBytes    = (ChunkBuffer.SizeInBytes - SizeInBytes)
  end
  CHUNK_ResetNewlineScanCache(ChunkBuffer)
  local ResultString = concat(Parts)
  return ResultString
end

local function CHUNK_MethodCountUntilNewLine (ChunkBuffer)
  -- Retrieve current state
  local FirstIndex     = ChunkBuffer.FirstIndex
  local FirstByteIndex = ChunkBuffer.FirstByteIndex
  local TailIndex      = ChunkBuffer.TailIndex
  local ScanIndex      = ChunkBuffer.ScanIndex
  local ScanOffset     = ChunkBuffer.ScanOffset
  local ScanCount      = ChunkBuffer.ScanCount
  -- Reset scan if behind current position
  if (ScanIndex < FirstIndex)
    or ((ScanIndex == FirstIndex) and (ScanOffset < FirstByteIndex))
  then
    ScanIndex  = FirstIndex
    ScanOffset = FirstByteIndex
    ScanCount  = 0
  end
  local Result
  -- Scan for newline
  while (Result == nil) and (ScanIndex <= TailIndex) do
    local Chunk        = ChunkBuffer.Queue[ScanIndex]
    local NewLineIndex = find(Chunk, "\n", ScanOffset, true)
    if NewLineIndex then
      Result = ScanCount + (NewLineIndex - ScanOffset + 1)
    else
      local Added = (#Chunk - ScanOffset + 1)
      if (Added > 0) then
        ScanCount = (ScanCount + Added)
      end
      ScanIndex  = (ScanIndex + 1)
      ScanOffset = 1
    end
  end
  -- Update scan cache if no newline found
  if (Result == nil) then
    ChunkBuffer.ScanIndex  = (ChunkBuffer.TailIndex + 1)
    ChunkBuffer.ScanOffset = 1
    ChunkBuffer.ScanCount  = ScanCount
  end
  return Result
end

local function CHUNK_MethodHasLf (ChunkBuffer)
  -- Check if a newline is present
  return (ChunkBuffer:countuntilnewline() ~= nil)
end

local function CHUNK_MethodTakeLine (ChunkBuffer)
  -- Get count until newline
  local CountUntilNewLine = ChunkBuffer:countuntilnewline()
  local Line
  if CountUntilNewLine then
    -- Consume the line including newline
    local LineAndNewLine = ChunkBuffer:consume(CountUntilNewLine)
    -- Remove newline characters
    if hassuffix(LineAndNewLine, "\r\n") then
      Line = removesuffix(LineAndNewLine, "\r\n")
    else
      Line = removesuffix(LineAndNewLine, "\n")
    end
  end
  return Line
end

local function CHUNK_MethodTakeAll (ChunkBuffer)
  -- Retrieve indices
  local FirstIndex = ChunkBuffer.FirstIndex
  local TailIndex  = ChunkBuffer.TailIndex
  local ResultString
  if (ChunkBuffer.SizeInBytes > 0) and (FirstIndex <= TailIndex) then
    -- Collect all parts
    local Parts           = {}
    local Index           = FirstIndex
    local FirstByteOffset = ChunkBuffer.FirstByteIndex
    if (FirstByteOffset > 1) then
      local FirstChunk   = ChunkBuffer.Queue[Index]
      local PartialChunk = sub(FirstChunk, FirstByteOffset)
      append(Parts, PartialChunk)
      Index = (Index + 1)
    end
    while (Index <= TailIndex) do
      local Chunk = ChunkBuffer.Queue[Index]
      append(Parts, Chunk)
      Index = (Index + 1)
    end
    ResultString = concat(Parts)
  else
    ResultString = ""
  end
  -- Reset buffer
  CHUNK_ResetState(ChunkBuffer)
  CHUNK_ResetNewlineScanCache(ChunkBuffer)
  return ResultString
end

local function NewChunkBuffer ()
  -- Create new ChunkBuffer object
  local ChunkBuffer = {
    append            = CHUNK_MethodAppend,
    len               = CHUNK_MethodLen,
    consume           = CHUNK_MethodConsume,
    countuntilnewline = CHUNK_MethodCountUntilNewLine,
    haslf             = CHUNK_MethodHasLf,
    takeline          = CHUNK_MethodTakeLine,
    takeall           = CHUNK_MethodTakeAll,
  }
  -- Initialize state
  CHUNK_ResetState(ChunkBuffer)
  CHUNK_ResetNewlineScanCache(ChunkBuffer)
  -- Return value
  return ChunkBuffer
end

--------------------------------------------------------------------------------
-- PUBLIC API                                                                 --
--------------------------------------------------------------------------------

local PUBLIC_API = {
  newchunkbuffer = NewChunkBuffer,
}

return PUBLIC_API
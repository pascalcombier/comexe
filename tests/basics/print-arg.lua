local insert = table.insert
if (arg[1] == "--print-warning") then
  warn("WARNING! 1")
  warn("@off")
  warn("WARNING!")
  warn("@on")
  warn("WARNING! 2")
else
  -- Sort the args by indices first to make it deterministic
  local Indices = {}
  for Key, Value in pairs(arg) do
    insert(Indices, Key)
  end
  table.sort(Indices)
  for Key, Index in pairs(Indices) do
    print(Index, arg[Index])
  end
end
GLOBAL_VARIABLE="print-arg.lua"

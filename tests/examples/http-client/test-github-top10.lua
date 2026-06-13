--------------------------------------------------------------------------------
-- MODULE                                                                     --
--------------------------------------------------------------------------------

local Http = require("socket.http")
local Json = require("dkjson")

local format = string.format

--------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS                                                          --
--------------------------------------------------------------------------------

local function GithubFetchTopRepositories ()
  local Uri  = "https://api.github.com/search/repositories?q=stars:>1&sort=stars&per_page=10"
  local Body = Http.request(Uri)
  local Repositories
  local ErrorString
  if Body then
    local JsonResponse, Position, DecodeErrorString = Json.decode(Body)
    if DecodeErrorString then
      ErrorString = DecodeErrorString
    elseif JsonResponse.message then
      ErrorString = format("API error: %s", JsonResponse.message)
    else
      Repositories = JsonResponse.items
    end
  else
    ErrorString = "Failed to fetch repository data"
  end
  return Repositories, ErrorString
end

--------------------------------------------------------------------------------
-- MAIN                                                                       --
--------------------------------------------------------------------------------

local Repositories, ErrorString = GithubFetchTopRepositories()

if Repositories then
  for Index, Repository in ipairs(Repositories) do
    print(format("%-40s %dk stars",
                 Repository.full_name,
                 (Repository.stargazers_count // 1000)))
  end
else
  io.stderr:write(format("%s\n", ErrorString))
  os.exit(1)
end

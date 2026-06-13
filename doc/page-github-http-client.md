# Fetching JSON data over HTTP

* [Introduction](#introduction)
* [Preparation](#preparation)
* [Writing the HTTP client](#writing-the-http-client)
  * [Initialization](#initialization)
  * [Making a HTTP GET request](#making-a-http-get-request)
  * [Parsing JSON from the response](#parsing-json-from-the-response)
  * [Listing the repositories](#listing-the-repositories)
* [Testing](#testing)
* [Compiling as a standalone binary](#compiling-as-a-standalone-binary)
* [Full listing](#full-listing)

# Introduction

This example fetches the **top 10 repositories from [GitHub](https://github.com)** sorted by stars. It shows how to build a **HTTP JSON client** with [LuaSocket](https://lunarmodules.github.io/luasocket/index.html) and [dkjson](https://dkolf.de/dkjson-lua/). The example uses only `GET`, and more features are covered in the [LuaSocket HTTP documentation](https://lunarmodules.github.io/luasocket/http.html).

```
> github-top10.exe
codecrafters-io/build-your-own-x         514k stars
sindresorhus/awesome                     475k stars
freeCodeCamp/freeCodeCamp                446k stars
public-apis/public-apis                  441k stars
EbookFoundation/free-programming-books   390k stars
openclaw/openclaw                        378k stars
nilbuild/developer-roadmap               356k stars
donnemartin/system-design-primer         352k stars
jwasham/coding-interview-university      351k stars
vinta/awesome-python                     302k stars
```

This example runs on both Windows and Linux.

# Preparation

Download the [latest ComEXE binaries](https://github.com/pascalcombier/comexe/releases) and the [dkjson](https://dkolf.de/dkjson-lua) library. Project structure:

```
github-top10\lua55ce-x86_64-windows.exe
github-top10\lua55ce-x86_64-linux
github-top10\src\dkjson.lua
github-top10\src\test-github-top10.lua
```

# Writing the HTTP client

## Initialization

```lua
local Http = require("socket.http")
local Json = require("dkjson")
```

## Making a HTTP GET request

[`socket.http`](https://lunarmodules.github.io/luasocket/http.html) returns the response body as a string.

```lua
local Uri  = "https://api.github.com/search/repositories?q=stars:>1&sort=stars&per_page=10"
local Body = Http.request(Uri)
```

## Parsing JSON from the response

[`dkjson.decode`](https://dkolf.de/dkjson-lua/) returns the JSON response as a Lua table:

```lua
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
```

## Listing the repositories

```lua
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
```

# Testing

Run the script:

```
> lua55ce-x86_64-windows.exe src\test-github-top10.lua
codecrafters-io/build-your-own-x         514k stars
sindresorhus/awesome                     475k stars
freeCodeCamp/freeCodeCamp                446k stars
public-apis/public-apis                  441k stars
EbookFoundation/free-programming-books   390k stars
openclaw/openclaw                        378k stars
nilbuild/developer-roadmap               356k stars
donnemartin/system-design-primer         352k stars
jwasham/coding-interview-university      351k stars
vinta/awesome-python                     302k stars
```

# Compiling as a standalone binary

From the command line:

```
> lua55ce-x86_64-windows.exe -x --make src\test-github-top10.lua
```

The executable is named after the script file:

```
> test-github-top10.exe
codecrafters-io/build-your-own-x         514k stars
sindresorhus/awesome                     475k stars
freeCodeCamp/freeCodeCamp                446k stars
public-apis/public-apis                  441k stars
EbookFoundation/free-programming-books   390k stars
openclaw/openclaw                        378k stars
nilbuild/developer-roadmap               356k stars
donnemartin/system-design-primer         352k stars
jwasham/coding-interview-university      351k stars
vinta/awesome-python                     302k stars
```

# Full listing

* **[test-github-top10.lua](../tests/examples/http-client/test-github-top10.lua)**

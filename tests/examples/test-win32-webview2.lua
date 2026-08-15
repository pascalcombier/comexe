local Runtime = require("com.runtime")
local webview = require("com.webview2")
local win32   = require("com.win32")

-- Try to load WebView2Loader.dll
local InitSuccess, InitErrorString = webview.init()
if (not InitSuccess) then
  win32.messagebox(nil, InitErrorString, "Application Error", "OK", "ERROR")
  os.exit(1)
end

-- Read the HTML code from file (dev) or from executable (production)
local Html = Runtime.loadresource("test-win32-webview2.html")
if (not Html) then
  win32.messagebox(nil, "Failed to read test-win32-webview2.html", "Application Error", "OK", "ERROR")
  os.exit(1)
end

local WindowCount = 1

-- WebView event callback
local function WebViewEventHandler (WebView, UiEvent)
  if (UiEvent == "hello") then
    local NewEvent = { type = "alert", text = "Hello from Lua!" }
    WebView:send(NewEvent)
  elseif (UiEvent == "new") then
    WindowCount = (WindowCount + 1)
    local Child = webview.new(Html, WebViewEventHandler)
    local Title = string.format("WebView2 Hello - %d", WindowCount)
    Child:show(Title)
  elseif (UiEvent == "exit") then
    WebView:close()
  end
end

-- New webview window
local WebView = webview.new(Html, WebViewEventHandler)
local Title   = string.format("WebView2 Hello - %d", WindowCount)
WebView:show(Title)

-- Wait for all the windows to be closed by the user
webview.runloop()
webview.cleanup()

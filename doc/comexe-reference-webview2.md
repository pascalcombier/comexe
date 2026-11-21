# WebView2 reference

* [Overview](#overview)
* [Initialization](#initialization)
* [Module API](#module-api)
  * [new](#new)
  * [runloop](#runloop)
* [WebView objects](#webview-objects)
* [Event management](#event-management)
  * [JavaScript to Lua](#javascript-to-lua)
  * [Lua to JavaScript](#lua-to-javascript)
* [Window title](#window-title)
* [Files dropped into the WebView](#files-dropped-into-the-webview)
  * [Capturing the dropped files](#capturing-the-dropped-files)
  * [Reading the paths in Lua](#reading-the-paths-in-lua)
* [Advanced features](#advanced-features)
  * [JavaScript execution](#javascript-execution)
  * [DevTools Protocol access](#devtools-protocol-access)
  * [Recording screenshots](#recording-screenshots)

# Overview

This module provides an interface to [Microsoft's WebView2](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) for building **Windows GUI applications**.

**Features**

- Display Web pages
   - From HTML/CSS/JavaScript code
   - From an HTTP server
- Event management
   - From JavaScript to Lua
   - From Lua to JavaScript
- Multiple windows
- Advanced features
   - JavaScript execution
   - DevTools Protocol access
   - Recording screenshots

**Requirements**

- [WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) must be installed
- `WebView2Loader.dll` must be resolvable (in the executable directory or in `PATH`)

# Initialization

`webview.init` must be called first:

```lua
local webview = require("com.webview2")
local win32   = require("com.win32")

local Success, ErrorString = webview.init("C:\\MyAppUserDataFolder")
if (not Success) then
  win32.messagebox(nil, ErrorString, "Application Error", "OK", "ERROR")
  os.exit(1)
end
```

The parameter is optional. When omitted, WebView2 stores [its data](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/user-data-folder) (sessions, cookies, etc) in a default location.

```lua
local Success, ErrorString = webview.init() -- data folder is created automatically: "program.exe.WebView2"
```

It is recommended to specify a writable directory, such as `%USERPROFILE%`. The default location is created next to the executable and can fail in write-protected directories such as `Program Files`.

# Module API

| Function                                    | Description                                       |
|---------------------------------------------|---------------------------------------------------|
| `webview.new(Content, OnMessage, UserData)` | Create a hidden **WebView object**                |
| `webview.runloop()`                         | Run the message loop until all windows are closed |

## new

`webview.new(Content, OnMessage, UserData)`

- `Content`
  - Standalone HTML/CSS/JS string (handwritten or output of [Node.js](https://nodejs.org/) or [bun](https://bun.sh))
  - A URI starting with `http://`, `https://` or `file://`
- `OnMessage`
  - Event handler, called with `OnMessage(WebView, UiEvent, AdditionalObjects)`
  - `UiEvent` is the JSON value posted by JavaScript
  - `AdditionalObjects` is `nil` or an array of pathnames, see [Files dropped into the WebView](#files-dropped-into-the-webview)
- `UserData`
  - Optional user value, retrievable with `WebView:getuserdata()`

The returned value is a **WebView object** documented in the next section.

> **Important:** A WebView is created hidden by default. Call `WebView:show()` to make it visible.

## runloop

`webview.runloop()` runs the message loop until all windows are closed, then returns the exit code.

# WebView objects

| Method                               | Description                                                                                |
|--------------------------------------|--------------------------------------------------------------------------------------------|
| `show()`                             | Show the window (created hidden by `new`)                                                  |
| `close()`                            | Close the window                                                                           |
| `setbounds(X, Y, Width, Height)`     | Move or resize (`nil` keeps the current position or size)                                  |
| `setfullscreen(Enabled)`             | Enable or disable fullscreen                                                               |
| `send(Message)`                      | Send a Lua object to the JavaScript side, see [Event management](#event-management)        |
| `getuserdata()`                      | Return the `UserData` value passed to `new`                                                |
| `hwnd()`                             | Return the Win32 `HWND`                                                                    |
| `execute(JavaScript, Callback)`      | Execute JavaScript in the page, see [JavaScript execution](#javascript-execution)          |
| `devtools(Method, Params, Callback)` | Call a DevTools Protocol method, see [DevTools Protocol access](#devtools-protocol-access) |
| `screenshot(Callback)`               | Capture the full page as a PNG, see [Recording screenshots](#recording-screenshots)        |

# Event management

## JavaScript to Lua

JavaScript posts an event with:

```javascript
window.chrome.webview.postMessage(JSON.stringify(Value))
```

Example:

```html
<button onclick="window.chrome.webview.postMessage(JSON.stringify('hello'))">Hello</button>
```

On the Lua side, the `OnMessage` handler receives the decoded value:

```lua
local function OnMessage (WebView, UiEvent)
  if (UiEvent == "hello") then
    print("The button was pressed")
  end
end
```

## Lua to JavaScript

The Lua side posts an event with:

```lua
WebView:send(Message)
```

`Message` is any Lua value (string, table, number). It is serialized to JSON with [dkjson](https://dkolf.de/dkjson-lua).

Example:

```lua
WebView:send({ type = "alert", text = "Hello from Lua!" })
```

On the JavaScript side, the page receives it through the `message` listener:

```javascript
window.chrome.webview.addEventListener('message', function (Event) {
  if (Event.data.type === 'alert') alert(Event.data.text)
})
```

The page reads the value from `Event.data`.

# Window title

The window title follows `document.title`, so it can be set from HTML or JavaScript. It defaults to `"WebView2"` when the page reports no title.

The Lua side can change it once the page is ready:

```lua
WebView:execute("document.title = 'New title'")
```

# Files dropped into the WebView

The process starts in JavaScript with the `drop` event listener.

## Capturing the dropped files

JavaScript exposes only `name`, `size`, `type` and `lastModified`. To retrieve the pathname, post the file objects to the host with `postMessageWithAdditionalObjects`:

```javascript
zone.addEventListener('drop', function (Event) {
  // Do not open the dropped file in the page
  Event.preventDefault()
  // Like postMessage, but also carries File objects, so Lua can read their pathnames
  window.chrome.webview.postMessageWithAdditionalObjects(
    JSON.stringify({ type: "drop" }), Event.dataTransfer.files)
})
```

## Reading the paths in Lua

`OnMessage` receives an array of absolute pathnames in `AdditionalObjects`:

```lua
local function OnMessage (WebView, UiEvent, AdditionalObjects)
  if (AdditionalObjects) then
    print(AdditionalObjects[1]) -- for example: "C:\docs\README.md"
  end
end
```

`AdditionalObjects` is `nil` when no file was passed with the message.

# Advanced features

`WebView:send` and `OnMessage` are sufficient to build a GUI application.

Optional features:

- **JavaScript execution** - runs JavaScript in the page and returns the result, for example to read the DOM state
- **DevTools Protocol access** - calls Chrome DevTools Protocol methods
- **Recording screenshots** - captures the page content as an image

## JavaScript execution

`WebView:execute(JavaScript, Callback)` runs JavaScript in the page. `Callback` is optional.

Callback signature:

```
Callback(WebView, Result, ErrorString)
```

Example:

```lua
local function OnTitleResult (WebView, Result, ErrorString)
  if Result then
    print(Result) -- for example: "WebView2 Example"
  else
    print(ErrorString)
  end
end

WebView:execute("document.title", OnTitleResult)
```

## DevTools Protocol access

`WebView:devtools(Method, Params, Callback)` calls a [Chrome DevTools Protocol](https://chromedevtools.github.io/devtools-protocol/) method:

- `Method` is the CDP method name, for example `"Runtime.evaluate"`
- `Params` is an optional Lua table with the method parameters (default `{}`)

Callback signature:

```
Callback(WebView, Result, ErrorString)
```

Example:

```lua
local function OnEvaluateResult (WebView, Result, ErrorString)
  if Result then
    print(Result.result.value)
  else
    print(ErrorString)
  end
end

local EvalParameters = { expression = "document.title", returnByValue = true }

WebView:devtools("Runtime.evaluate", EvalParameters, OnEvaluateResult)
```

## Recording screenshots

`screenshot` is a specific use of [DevTools Protocol access](#devtools-protocol-access): it calls the [`Page.captureScreenshot`](https://chromedevtools.github.io/devtools-protocol/tot/Page/#method-captureScreenshot) method to capture the full page as a PNG image.

`WebView:screenshot(Callback)` captures the full page as PNG data, ready to be written to a file.

Callback signature:

```
Callback(WebView, PngImageData, ErrorString)
```

Example:

```lua
local function OnScreenshot (WebView, PngImageData, ErrorString)
  if PngImageData then
    local File = io.open("screenshot.png", "wb")
    if File then
      File:write(PngImageData)
      File:close()
    end
  else
    print(ErrorString)
  end
end

WebView:screenshot(OnScreenshot)
```

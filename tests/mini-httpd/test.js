/*============================================================================*/
/* INFORMATION                                                                */
/*============================================================================*/

/* Test:
 *   - GET
 *   - POST (urlencoded form data)
 *   - SSE connection
 *   - Chunked data
 */

/*============================================================================*/
/* GLOBAL VARIABLES                                                           */
/*============================================================================*/

const GLOBAL_LogText     = document.getElementById("log");
const GLOBAL_ServerState = document.getElementById("server-state");
let GLOBAL_WebSocket     = null;

/*============================================================================*/
/* PRIVATE FUNCTIONS                                                          */
/*============================================================================*/

function TEST_SetText (Element, Text, Option)
{
  Element.innerHTML = "";

  Element.classList.remove("box-loading");

  if (Option === "ERROR")
  {
    Element.classList.remove("box-info");
    Element.classList.add("box-error");
  }
  else
  {
    Element.classList.remove("box-error");
    Element.classList.add("box-info");
  }

  Element.innerHTML = Text;
}

function TEST_AppendLog (Line)
{
  const TextArea = GLOBAL_LogText;

  TextArea.value += `${Line}\n`;
}

function TEST_Assert (Timestamp, Condition, Message)
{
  if (Condition)
  {
    TEST_AppendLog(`[${Timestamp}] PASSED: ${Message}`);
  }
  else
  {
    TEST_AppendLog(`[${Timestamp}] FAILED: ${Message}`);
  }
}

/*============================================================================*/
/* TESTS                                                                      */
/*============================================================================*/

function TEST_TestGet (Timestamp)
{
  const URI = `/test-get-variables?test=123&foo=bar`;

  TEST_AppendLog(`[${Timestamp}] TEST GET ${URI}`);

  fetch(URI)
    .then(function (Result) {
      const StatusCode = (Result && Result.status);
      TEST_Assert(Timestamp, (StatusCode === 200), `status 200`);
      return Result.json();
    })
    .then(function (JsonObject) {
      if (JsonObject.test === '123' && JsonObject.foo === 'bar') {
        TEST_AppendLog(`[${Timestamp}] PASSED: /test-get-variables received expected values: ` + JSON.stringify(JsonObject));
      } else {
        TEST_AppendLog(`[${Timestamp}] /test-get-variables FAIL: unexpected values: ` + JSON.stringify(JsonObject));
      }
    })
    .catch(function (Error) {
      TEST_AppendLog(`[${Timestamp}] ERROR fetching /test-get-variables: ${Error}`);
    });
}

function TEST_RunPostUrlEncodedTest (Timestamp)
{
  TEST_AppendLog(`[${Timestamp}] TEST postUrlEncodedWithForm (sending {foo:"bar", num:123})`);

  const JsonObject = {
    foo: "bar",
    num: 123
  };

  const MyFormData = new FormData();

  for (const Key in JsonObject) {
    MyFormData.append(Key, JsonObject[Key]);
  }

  fetch("/test-post-urlencoded", {
    method: "POST",
    body:   MyFormData,
  })
  .then(function (Result) {
    TEST_AppendLog(`[${Timestamp}] PASSED: status: ${Result && Result.status}`);
    return Result.json();
  })
  .then(function (JsonObject) {
    if ((JsonObject.foo === "bar")
        && (JsonObject.num === 123 || JsonObject.num === '123'))
    {
      TEST_AppendLog(`[${Timestamp}] PASSED: received expected JSON: ${JSON.stringify(JsonObject)}`);
    } else {
      TEST_AppendLog(`[${Timestamp}] FAIL: JSON did not contain expected values: ${JSON.stringify(JsonObject)}`);
    }
  })
  .catch(function (Error) {
    TEST_AppendLog(`[${Timestamp}] ERROR sending post: ${Error}`);
  });
}

function TEST_RunPostUrlEncodedBodyTest (Timestamp)
{
  TEST_AppendLog(`[${Timestamp}] TEST post application/x-www-form-urlencoded (sending {foo:"bar", num:123})`);

  const Params = new URLSearchParams();
  Params.append("foo", "bar");
  Params.append("num", "123");

  fetch("/test-post-urlencoded-form", {
    method:  "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" },
    body:    Params.toString(),
  })
  .then(function (Result) {
    const StatusCode = (Result && Result.status);
    TEST_Assert(Timestamp, (StatusCode === 200), `status 200 for /test-post-urlencoded-form`);
    return Result.json();
  })
  .then(function (JsonObject) {
    if ((JsonObject.foo === "bar") && (JsonObject.num === 123 || JsonObject.num === "123"))
    {
      TEST_AppendLog(`[${Timestamp}] PASSED: urlencoded form parsed as expected: ${JSON.stringify(JsonObject)}`);
    }
    else
    {
      TEST_AppendLog(`[${Timestamp}] FAIL: urlencoded form unexpected JSON: ${JSON.stringify(JsonObject)}`);
    }
  })
  .catch(function (Error) {
    TEST_AppendLog(`[${Timestamp}] ERROR sending urlencoded post: ${Error}`);
  });
}

/*============================================================================*/
/* SSE EVENTS                                                                 */
/*============================================================================*/

var MAIN_TestState = "INIT";

function SSE_OnOpenCallback ()
{
  if ((MAIN_TestState === "INIT") || (MAIN_TestState === "DISCONNECTED"))
  {
    TEST_SetText(GLOBAL_ServerState, "SSE connected, test running", "INFO");
    GLOBAL_ServerState.classList.add("has-throbber");
    MAIN_TestState = "CONNECTED";
  }
}

function SSE_OnErrorCallback (Error)
{
  if ((MAIN_TestState === "INIT") || (MAIN_TestState === "CONNECTED"))
  {
    GLOBAL_ServerState.classList.remove("has-throbber");
    TEST_SetText(GLOBAL_ServerState, "SSE disconnected", "ERROR");
    MAIN_TestState = "DISCONNECTED";
  }
}

function SSE_OnMessageCallback (Event) 
{
  /* Extract the time from ISOString */
  const Timestamp  = new Date().toISOString().substring(11, 19);
  const Message    = Event.data;
  const JsonObject = JSON.parse(Message);
  const Count      = JsonObject.count;

  TEST_AppendLog(`[${Timestamp}] countdown value: ${Count}`);

  if (Count == 6) {
    try {
      TEST_TestGet(Timestamp);
    } catch (Error) {
      TEST_AppendLog(`[${Timestamp}] TEST_RunTest1 error: ${Error}`);
    }
  }
  else if (Count == 5) {
    try {
      TEST_RunPostUrlEncodedTest(Timestamp);
    } catch (Error) {
      TEST_AppendLog(`[${Timestamp}] TEST_RunPostUrlEncodedTest error: ${Error}`);
    }
  }
  else if (Count == 4) {
    fetch("/test-chunk-data")
      .then(function (Result) {
        const StatusCode = (Result && Result.status);
        TEST_Assert(Timestamp, (StatusCode === 200), `status 200 for /test-chunk-data`);
        return Result.json();
      })
      .then(function (JsonObject) {
        TEST_Assert(Timestamp, JsonObject.Success, `/test-chunk-data received expected data`);
      })
      .catch(function (Error) {
        TEST_AppendLog(`[${Timestamp}] ERROR fetching /test-chunk-data: ${Error}`);
      });
  }
  else if (Count == 3) {
    try {
      TEST_RunPostUrlEncodedBodyTest(Timestamp);
    } catch (Error) {
      TEST_AppendLog(`[${Timestamp}] TEST_RunPostUrlEncodedBodyTest error: ${Error}`);
    }
  }
  else if (Count == 2) {
    try {
      const Protocol = (window.location.protocol === "https:") ? "wss:" : "ws:";
      const WS_URL   = `${Protocol}//${window.location.host}/ws`;
      TEST_AppendLog(`[${Timestamp}] TEST WebSocket connection to ${WS_URL}`);
      GLOBAL_WebSocket = new WebSocket(WS_URL);
      const Socket = GLOBAL_WebSocket;
      Socket.onopen = function () {
        TEST_AppendLog(`[${Timestamp}] PASSED: WebSocket connected`);
        Socket.send("hello");
      };
      Socket.onmessage = function (Event) {
        TEST_AppendLog(`[${Timestamp}] PASSED: WebSocket received: ${Event.data}`);
      };
      Socket.onerror = function (Error) {
        TEST_AppendLog(`[${Timestamp}] FAILED: WebSocket error`);
      };
      Socket.onclose = function () {
        TEST_AppendLog(`[${Timestamp}] WebSocket closed`);
        GLOBAL_WebSocket = null;
      };
    } catch (Error) {
      TEST_AppendLog(`[${Timestamp}] WebSocket exception: ${Error}`);
    }
  }
  else if (Count == 0) {
    try {
      if (GLOBAL_WebSocket) {
        try {
          GLOBAL_WebSocket.close();
        } catch (WSError) {
          TEST_AppendLog(`[${Timestamp}] WebSocket close error: ${WSError}`);
        }
        GLOBAL_WebSocket = null;
      }
      TEST_EventSource.close();
    } catch (ErrorMessage) {
      TEST_AppendLog(`[${Timestamp}] TEST_EventSource.close error: ${ErrorMessage}`);
    }
    GLOBAL_ServerState.classList.remove("has-throbber");
    TEST_AppendLog("Program closed");
    TEST_SetText(GLOBAL_ServerState, "SSE closed", "ERROR");
  }
}

/*============================================================================*/
/* MAIN                                                                       */
/*============================================================================*/

const TEST_EventSource = new EventSource("/sse");

TEST_EventSource.onopen    = SSE_OnOpenCallback;
TEST_EventSource.onmessage = SSE_OnMessageCallback;
TEST_EventSource.onerror   = SSE_OnErrorCallback;

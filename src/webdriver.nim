import httpclient, uri, json, tables

type
  WebDriver* = ref object
    url*: Uri
    client*: HttpClient

  Session* = object
    driver: WebDriver
    id*: string

  WebDriverException* = object of Exception

  ProtocolException* = object of WebDriverException

proc newWebDriver*(url: string = "http://localhost:4444"): WebDriver =
  WebDriver(url: url.parseUri, client: newHttpClient())

proc createSession*(self: WebDriver): Session =
  # Check the readiness of the Web Driver.
  let resp = self.client.getContent($(self.url / "status"))
  let obj = parseJson(resp)

  if obj{"value", "ready"}.isNil():
    let msg = "Readiness message does not follow spec"
    raise newException(ProtocolException, msg)

  if not obj{"value", "ready"}.getBVal():
    raise newException(WebDriverException, "WebDriver is not ready")

  # Create our session.
  let sessionReq = %*{"capabilities": {"browserName": "firefox"}}
  let sessionResp = self.client.postContent($(self.url / "session"),
                                            $sessionReq)
  let sessionObj = parseJson(sessionResp)
  if sessionObj{"value", "sessionId"}.isNil():
    raise newException(ProtocolException, "No sessionId in response to request")

  return Session(id: sessionObj["value"]["sessionId"].getStr(), driver: self)

proc navigate*(self: Session, url: string) =
  let reqUrl = $(self.driver.url / "session" / self.id / "url")
  let obj = %*{"url": url}
  let resp = self.driver.client.postContent(reqUrl, $obj)

  let respObj = parseJson(resp)
  if respObj{"value"}.getFields().len != 0:
    raise newException(WebDriverException, $respObj)

proc getPageSource*(self: Session): string =
  let reqUrl = $(self.driver.url / "session" / self.id / "source")
  let resp = self.driver.client.getContent(reqUrl)

  let respObj = parseJson(resp)
  if respObj{"value"}.isNil:
    raise newException(WebDriverException, $respObj)

  return respObj{"value"}.getStr()

when isMainModule:
  let webDriver = newWebDriver()
  let session = webDriver.createSession()
  echo(session)
  session.navigate("https://picheta.me")
  echo(session.getPageSource())

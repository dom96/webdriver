# For reference, this is brilliant: https://github.com/jlipps/simple-wd-spec

import httpclient, uri, json, tables, options, strutils, unicode

type
  WebDriver* = ref object
    url*: Uri
    client*: HttpClient

  Session* = object
    driver: WebDriver
    id*: string

  Element* = object
    session: Session
    id*: string

  LocationStrategy* = enum
    CssSelector, LinkTextSelector, PartialLinkTextSelector, TagNameSelector,
    XPathSelector

  WebDriverException* = object of Exception

  ProtocolException* = object of WebDriverException

proc toKeyword(strategy: LocationStrategy): string =
  case strategy
  of CssSelector: "css selector"
  of LinkTextSelector: "link text"
  of PartialLinkTextSelector: "partial link text"
  of TagNameSelector: "tag name"
  of XPathSelector: "xpath"

proc checkResponse(resp: string): JsonNode =
  result = parseJson(resp)
  if result{"value"}.isNil:
    raise newException(WebDriverException, $result)

proc newWebDriver*(url: string = "http://localhost:4444"): WebDriver =
  WebDriver(url: url.parseUri, client: newHttpClient())

proc createSession*(self: WebDriver): Session =
  ## Creates a new browsing session.

  # Check the readiness of the Web Driver.
  let resp = self.client.getContent($(self.url / "status"))
  let obj = parseJson(resp)
  let ready = obj{"value", "ready"}

  if ready.isNil():
    let msg = "Readiness message does not follow spec"
    raise newException(ProtocolException, msg)

  if not ready.getBool():
    raise newException(WebDriverException, "WebDriver is not ready")

  # Create our session.
  let sessionReq = %*{"capabilities": {"browserName": "firefox"}}
  let sessionResp = self.client.postContent($(self.url / "session"),
                                            $sessionReq)
  let sessionObj = parseJson(sessionResp)
  let sessionId = sessionObj{"value", "sessionId"}
  if sessionId.isNil():
    raise newException(ProtocolException, "No sessionId in response to request")

  return Session(id: sessionId.getStr(), driver: self)

proc close*(self: Session) =
  let reqUrl = $(self.driver.url / "session" / self.id)
  let resp = self.driver.client.request(reqUrl, HttpDelete)

  let respObj = checkResponse(resp.body)

proc navigate*(self: Session, url: string) =
  ## Instructs the session to navigate to the specified URL.
  let reqUrl = $(self.driver.url / "session" / self.id / "url")
  let obj = %*{"url": url}
  let resp = self.driver.client.postContent(reqUrl, $obj)

  let respObj = parseJson(resp)
  if respObj{"value"}.getFields().len != 0:
    raise newException(WebDriverException, $respObj)

proc getPageSource*(self: Session): string =
  ## Retrieves the specified session's page source.
  let reqUrl = $(self.driver.url / "session" / self.id / "source")
  let resp = self.driver.client.getContent(reqUrl)

  let respObj = checkResponse(resp)

  return respObj{"value"}.getStr()

proc findElement*(self: Session, selector: string,
                  strategy = CssSelector): Option[Element] =
  let reqUrl = $(self.driver.url / "session" / self.id / "element")
  let reqObj = %*{"using": toKeyword(strategy), "value": selector}
  let resp = self.driver.client.post(reqUrl, $reqObj)
  if resp.status == Http404:
    return none(Element)

  if resp.status != Http200:
    raise newException(WebDriverException, resp.status)

  let respObj = checkResponse(resp.body)

  for key, value in respObj["value"].getFields().pairs():
    return some(Element(id: value.getStr(), session: self))

proc getText*(self: Element): string =
  let reqUrl = $(self.session.driver.url / "session" / self.session.id /
                 "element" / self.id / "text")
  let resp = self.session.driver.client.getContent(reqUrl)
  let respObj = checkResponse(resp)

  return respObj["value"].getStr()

proc click*(self: Element) =
  let reqUrl = $(self.session.driver.url / "session" / self.session.id / 
                 "element" / self.id / "click")
  let obj = %*{}
  let resp = self.session.driver.client.post(reqUrl, $obj)
  if resp.status != Http200:
    raise newException(WebDriverException, resp.status)

  discard checkResponse(resp.body)

# Note: There currently is an open bug in geckodriver that causes DOM events not to fire when sending keys.
# https://github.com/mozilla/geckodriver/issues/348
proc sendKeys*(self: Element, text: string) =
  let reqUrl = $(self.session.driver.url / "session" / self.session.id /
                 "element" / self.id / "value")
  let obj = %*{"text": text}
  let resp = self.session.driver.client.post(reqUrl, $obj)
  if resp.status != Http200:
    raise newException(WebDriverException, resp.status)

  discard checkResponse(resp.body)

type
  # https://w3c.github.io/webdriver/#keyboard-actions
  Key* = enum
    Unidentified = 0,
    Cancel,
    Help,
    Backspace,
    Tab,
    Clear,
    Return,
    Enter,
    Shift,
    Control,
    Alt,
    Pause,
    Escape

proc toUnicode(key: Key): Rune =
  Rune(0xE000 + ord(key))

proc press*(self: Session, keys: varargs[Key]) =
  let reqUrl = $(self.driver.url / "session" / self.id / "actions")
  let obj = %*{"actions": [
    {
      "type": "key",
      "id": "keyboard",
      "actions": []
    }
  ]}
  for key in keys:
    obj["actions"][0]["actions"].elems.add(
      %*{
        "type": "keyDown",
        "value": $toUnicode(key)
      }
    )
    obj["actions"][0]["actions"].elems.add(
      %*{
        "type": "keyUp",
        "value": $toUnicode(key)
      }
    )

  let resp = self.driver.client.post(reqUrl, $obj)
  if resp.status != Http200:
    raise newException(WebDriverException, resp.status)

  discard checkResponse(resp.body)

when isMainModule:
  let webDriver = newWebDriver()
  let session = webDriver.createSession()
  let amazonUrl = "https://www.amazon.co.uk/Nintendo-Classic-Mini-" &
                  "Entertainment-System/dp/B073BVHY3F"
  session.navigate(amazonUrl)

  echo session.findElement("#priceblock_ourprice").get().getText()

  session.close()

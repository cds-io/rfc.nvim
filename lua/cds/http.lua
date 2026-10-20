-- HTTP through curl. Every option travels as a config file on stdin
-- (`--config -`), so a bearer token or client secret never appears in argv or
-- in `ps`. An HTTP response of any status returns normally; only a transport
-- failure returns nil plus a classified error.
local proc = require("cds.proc")

local M = {}

---@class cds.http.Request
---@field method string
---@field url string
---@field headers table<string, string>?
---@field body string?
---@field timeout integer?      -- seconds for curl's --max-time; default 30

---@class cds.http.Response
---@field status integer
---@field headers table<string, string>   -- lower-cased names
---@field body string

---@class cds.http.Error
---@field kind "unreachable"|"timeout"|"interrupted"|"tls"|"curl"|"spawn"
---@field message string

-- A private separator: curl prints it, then the status, after the body.
local MARK = "\n--cds-http-status:"

-- 52, 55 and 56 (empty reply, send failure, receive failure) happen after the
-- request may have left the machine, like a timeout, so they are "interrupted"
-- and the caller treats them as it treats a timeout.
local kinds = {
  [6] = "unreachable",
  [7] = "unreachable",
  [28] = "timeout",
  [35] = "tls",
  [52] = "interrupted",
  [55] = "interrupted",
  [56] = "interrupted",
  [60] = "tls",
}

--- Quotes a value for a curl config file: `"..."` with backslash escapes.
---@param s string
---@return string
function M.quote(s)
  return '"'
    .. s:gsub('[\\"\n\r\t]', { ["\\"] = "\\\\", ['"'] = '\\"', ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" })
    .. '"'
end

--- The config text for a request; exposed for specs.
---@param req cds.http.Request
---@return string
function M.config(req)
  local lines = {
    "silent",
    "show-error",
    "dump-header = " .. M.quote("-"),
    "max-time = " .. tostring(req.timeout or 30),
    "write-out = " .. M.quote(MARK .. "%{http_code}"),
    "request = " .. M.quote(req.method),
    "url = " .. M.quote(req.url),
  }
  for _, name in ipairs(vim.tbl_keys(req.headers or {})) do
    table.insert(lines, "header = " .. M.quote(name .. ": " .. req.headers[name]))
  end
  if req.body then
    -- data-raw: a body starting with "@" is data, where data-binary would
    -- read a file of that name.
    table.insert(lines, "data-raw = " .. M.quote(req.body))
  end
  table.sort(lines)
  return table.concat(lines, "\n") .. "\n"
end

--- Splits curl's stdout (dumped headers, body, then the write-out) into a Response.
---@param out string
---@return cds.http.Response?
function M.parse(out)
  local mark = out:find(MARK, 1, true)
  if not mark then
    return nil
  end
  local status = tonumber(out:sub(mark + #MARK))
  local raw = out:sub(1, mark - 1)
  -- Header blocks end at a blank line; a redirect or 100-continue leaves
  -- several blocks, and the last one is the response we want.
  local headers, body = {}, raw
  while true do
    local head, rest = body:match("^(HTTP/[^\r\n]*\r?\n.-\r?\n)\r?\n(.*)$")
    if not head then
      break
    end
    headers = {}
    for name, value in head:gmatch("\n([^:\r\n]+):%s*([^\r\n]*)") do
      headers[name:lower()] = value
    end
    body = rest
  end
  return { status = status, headers = headers, body = body }
end

--- Set to a function to be told about every request: { method, url (without
--- its query), status or kind, ms }. Headers and bodies are never passed.
---@type (fun(rec: { method: string, url: string, status: integer?, kind: string?, ms: integer }))?
M.trace = nil

---@param req cds.http.Request
---@return cds.http.Response? response
---@return cds.http.Error? err
local function perform(req)
  local r, spawn_err = proc.run(
    { "curl", "--config", "-" },
    { stdin = M.config(req), timeout = ((req.timeout or 30) + 5) * 1000 }
  )
  if not r then
    return nil, { kind = "spawn", message = spawn_err }
  end
  if r.code ~= 0 then
    local kind = r.timed_out and "timeout" or kinds[r.code] or "curl"
    local detail = vim.trim(r.stderr)
    return nil, { kind = kind, message = ("curl exit %d%s"):format(r.code, detail ~= "" and ": " .. detail or "") }
  end
  local res = M.parse(r.stdout)
  if not res then
    return nil, { kind = "curl", message = "curl produced no status" }
  end
  return res
end

---@param req cds.http.Request
---@return cds.http.Response? response
---@return cds.http.Error? err
function M.request(req)
  local started = vim.uv.hrtime()
  local res, err = perform(req)
  if M.trace then
    pcall(M.trace, {
      method = req.method,
      url = (req.url:gsub("[?#].*$", "")),
      status = res and res.status or nil,
      kind = err and err.kind or nil,
      ms = math.floor((vim.uv.hrtime() - started) / 1e6),
    })
  end
  return res, err
end

return M

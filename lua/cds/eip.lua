-- Ethereum improvement proposals, read: the frontmatter, the headings and
-- fenced code of the markdown body, the EIP and ERC mentions a line makes,
-- and the listing page (eips.ethereum.org/all, ercs.ethereum.org/all) as
-- entries. Plain lines in, plain tables out; nothing here names the editor.
local M = {}

---@class cds.eip.Heading
---@field level integer   -- the number of # signs
---@field title string
---@field line integer

---@class cds.eip.Fence
---@field first integer   -- the opening ``` line
---@field last integer    -- the closing ``` line, or the last line when unterminated
---@field lang string     -- the info string after the fence, "" when none

---@class cds.eip.Mention
---@field kind "eip"|"erc"
---@field first integer   -- byte range of the text a link would replace
---@field last integer
---@field id string

---@class cds.eip.Entry
---@field id string
---@field title string
---@field status string   -- the listing's section: "Final", "Draft", ...

---@param s string
---@return string
local function trim(s)
  return (s:match("^%s*(.-)%s*$"))
end

--- The YAML frontmatter as a table of strings, and the first line of the
--- body. A value on the lines that follow its key (indented) is joined to
--- it. Without a frontmatter the table is empty and the body starts at 1.
---@param lines string[]
---@return table<string, string> fields
---@return integer body
function M.frontmatter(lines)
  if lines[1] ~= "---" then
    return {}, 1
  end
  local fields, key = {}, nil
  for i = 2, #lines do
    local line = lines[i]
    if line == "---" then
      return fields, i + 1
    end
    local k, v = line:match("^([%w%-]+):%s*(.-)%s*$")
    if k then
      key, fields[k] = k, v
    elseif key and line:match("^%s+%S") then
      fields[key] = (fields[key] == "" and "" or fields[key] .. " ") .. trim(line)
    end
  end
  return fields, #lines + 1
end

--- The fenced code blocks, so a # inside one is not a heading.
---@param lines string[]
---@return cds.eip.Fence[]
function M.fences(lines)
  local fences, open = {}, nil
  for i, line in ipairs(lines) do
    local lang = line:match("^%s*```%s*(.-)%s*$")
    if lang then
      if open then
        open.last = i
        table.insert(fences, open)
        open = nil
      else
        open = { first = i, lang = lang }
      end
    end
  end
  if open then
    open.last = #lines
    table.insert(fences, open)
  end
  return fences
end

---@param fences cds.eip.Fence[]
---@return fun(i: integer): boolean
local function fenced(fences)
  return function(i)
    for _, f in ipairs(fences) do
      if i >= f.first and i <= f.last then
        return true
      end
    end
    return false
  end
end

--- The headings of the body, outside fenced code.
---@param lines string[]
---@return cds.eip.Heading[]
function M.headings(lines)
  local headings, inside = {}, fenced(M.fences(lines))
  for i, line in ipairs(lines) do
    local hashes, title = line:match("^(#+)%s+(.-)%s*#*%s*$")
    if hashes and not inside(i) then
      table.insert(headings, { level = #hashes, title = title, line = i })
    end
  end
  return headings
end

--- The numbers a `requires:` field names.
---@param fields table<string, string>
---@return string[]
function M.requires(fields)
  local ids = {}
  for id in (fields.requires or ""):gmatch("%d+") do
    table.insert(ids, id)
  end
  return ids
end

--- Every EIP or ERC a line mentions, in order of position: a markdown link
--- whose text names one ("[EIP-2718](./eip-2718.md)", the whole link) and a
--- bare "EIP-155" or "ERC-20". The kind is the one the text uses.
---@param line string
---@return cds.eip.Mention[]
function M.mentions(line)
  local found = {}
  local pos = 1
  while true do
    local first, last, kind, id = line:find("%[(E[IR][PC])%-(%d+)%]%(%./[%w%-/%.]+%)", pos)
    if not first then
      break
    end
    table.insert(found, { kind = kind:lower(), first = first, last = last, id = id })
    pos = last + 1
  end
  local function inside_link(i)
    for _, m in ipairs(found) do
      if i >= m.first and i <= m.last then
        return true
      end
    end
    return false
  end
  pos = 1
  while true do
    local first, last, kind, id = line:find("(E[IR][PC])%-(%d+)", pos)
    if not first then
      break
    end
    local before = line:sub(first - 1, first - 1)
    local after = line:sub(last + 1, last + 1)
    if not inside_link(first) and not before:match("[%w%-]") and not after:match("%w") then
      table.insert(found, { kind = kind:lower(), first = first, last = last, id = id })
    end
    pos = last + 1
  end
  table.sort(found, function(a, b)
    return a.first < b.first
  end)
  return found
end

local ENTITIES =
  { ["&amp;"] = "&", ["&lt;"] = "<", ["&gt;"] = ">", ["&quot;"] = '"', ["&#39;"] = "'", ["&nbsp;"] = " " }

---@param s string
---@return string
local function unescape(s)
  return (s:gsub("&[%w#]+;", function(e)
    return ENTITIES[e] or e
  end))
end

--- The listing page as entries: each table row's number and title, under
--- the status heading the row sits beneath.
---@param lines string[]
---@return cds.eip.Entry[]
function M.listing(lines)
  local entries, status, entry = {}, "", nil
  for _, line in ipairs(lines) do
    local heading = line:match("<h2 [^>]*>(.-)</h2>")
    if heading then
      status = trim(unescape(heading))
    end
    local id = line:match('class="eipnum"><a [^>]*>(%d+)</a>')
    if id then
      entry = { id = id, title = "", status = status }
      table.insert(entries, entry)
    end
    local title = entry and line:match('class="title">(.-)</td>')
    if title then
      entry.title = trim(unescape((title:gsub("<[^>]->", ""))))
    end
  end
  return entries
end

return M

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

---@class cds.eip.Table
---@field first integer      -- the first line of the table in the text
---@field last integer       -- the last
---@field header boolean     -- whether the first row is a heading row
---@field rows string[][]    -- each row's cells, as plain text

---@class cds.eip.Block
---@field kind "heading"|"fence"|"table"|"line"
---@field line integer        -- the block's first line in the text
---@field level integer|nil   -- heading: the number of # signs
---@field title string|nil    -- heading: the title, plain
---@field lang string|nil     -- fence: the info string, "" when none
---@field code string[]|nil   -- fence: the lines between the fences, as written
---@field header boolean|nil  -- table: whether the first row is a heading row
---@field rows string[][]|nil -- table: the cells, plain
---@field text string|nil     -- line: the line, plain; "" for a blank line

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
--- bare "EIP-155" or "ERC-20". The kind is the one the text uses. The links
--- are blanked out of the line the bare scan reads, so a link's text is
--- found once, and a bare mention after a link keeps its position.
---@param line string
---@return cds.eip.Mention[]
function M.mentions(line)
  local found = {}
  local LINK = "%[(E[IR][PC])%-(%d+)%]%(%./[%w%-/%.]+%)"
  for first, kind, id, after in line:gmatch("()" .. LINK .. "()") do
    table.insert(found, { kind = kind:lower(), first = first, last = after - 1, id = id })
  end
  local bare = line
  for _, m in ipairs(found) do
    bare = bare:sub(1, m.first - 1) .. (" "):rep(m.last - m.first + 1) .. bare:sub(m.last + 1)
  end
  for first, kind, id, after in bare:gmatch("()(E[IR][PC])%-(%d+)()") do
    local before = bare:sub(first - 1, first - 1)
    local following = bare:sub(after, after)
    if not before:match("[%w%-]") and not following:match("%w") then
      table.insert(found, { kind = kind:lower(), first = first, last = after - 1, id = id })
    end
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

--- Markdown inline markup and inline HTML as plain text: tags dropped (a
--- <code> span becomes backticks), entities unescaped, **bold** and *em* as
--- their text. A code span is kept as written, and so is an autolink
--- (<https://...>), which is no tag.
---@param s string
---@return string
function M.plain(s)
  local spans = {}
  s = s:gsub("`[^`]*`", function(span)
    table.insert(spans, span)
    return "\1" .. #spans .. "\1"
  end)
  s = s:gsub("<code>(.-)</code>", "`%1`")
  s = s:gsub("</?%a[%w%-]*%s[^>]*>", ""):gsub("</?%a[%w%-]*/?>", "")
  s = unescape(s)
  s = s:gsub("%*%*([^*]-)%*%*", "%1")
  s = s:gsub("%*([^%s*][^*]-)%*", "%1")
  return (s:gsub("\1(%d+)\1", function(n)
    return spans[tonumber(n)]
  end))
end

--- A pipe table's cells: the text between the bars, trimmed and plain.
---@param line string
---@return string[]
local function pipe_cells(line)
  local cells = {}
  for cell in line:gsub("^%s*|", ""):gsub("|%s*$", ""):gmatch("[^|]+") do
    table.insert(cells, trim(M.plain(cell)))
  end
  return cells
end

--- Every table in the text, HTML (<table>...</table>, as pandoc writes
--- them) or markdown (a row of bars, then the |---|---| rule, then rows),
--- as rows of plain-text cells.
---@param lines string[]
---@return cds.eip.Table[]
function M.tables(lines)
  local tables = {}
  local i = 1
  while i <= #lines do
    if lines[i]:match("^%s*<table") then
      local last = i
      while last < #lines and not lines[last]:match("</table>") do
        last = last + 1
      end
      local rows, header = {}, false
      local block = table.concat(lines, "\n", i, last)
      for row in block:gmatch("<tr.-</tr>") do
        local cells = {}
        for cell in row:gmatch("<t[dh][^>]*>(.-)</t[dh]>") do
          table.insert(cells, trim(M.plain((cell:gsub("\n", " ")))))
        end
        if #rows == 0 and row:match("<th") then
          header = true
        end
        table.insert(rows, cells)
      end
      table.insert(tables, { first = i, last = last, header = header, rows = rows })
      i = last + 1
    elseif lines[i]:match("^%s*|.*|%s*$") and lines[i + 1] and lines[i + 1]:match("^%s*|[%s:%-|]+|%s*$") then
      local rows = { pipe_cells(lines[i]) }
      local last = i + 1
      while last < #lines and lines[last + 1]:match("^%s*|.*|%s*$") do
        last = last + 1
        table.insert(rows, pipe_cells(lines[last]))
      end
      table.insert(tables, { first = i, last = last, header = true, rows = rows })
      i = last + 1
    else
      i = i + 1
    end
  end
  return tables
end

--- The body as blocks, every piece of text already plain: a heading, a
--- fenced code block, a table, or one line. This is the view a renderer
--- folds over, so no kind of text can miss the plain-text pass.
---@param lines string[]
---@param from? integer   -- the first body line; 1 unless given
---@return cds.eip.Block[]
function M.blocks(lines, from)
  local fence_at, table_at, skip = {}, {}, {}
  for _, f in ipairs(M.fences(lines)) do
    fence_at[f.first] = f
    for i = f.first, f.last do
      skip[i] = true
    end
  end
  for _, t in ipairs(M.tables(lines)) do
    table_at[t.first] = t
    for i = t.first, t.last do
      skip[i] = true
    end
  end
  local heading_at = {}
  for _, h in ipairs(M.headings(lines)) do
    heading_at[h.line] = h
  end
  local blocks = {}
  for i = from or 1, #lines do
    if fence_at[i] then
      local f = fence_at[i]
      local last = lines[f.last]:match("^%s*```") and f.last ~= f.first and f.last - 1 or f.last
      local code = {}
      for j = f.first + 1, last do
        table.insert(code, lines[j])
      end
      table.insert(blocks, { kind = "fence", line = i, lang = f.lang, code = code })
    elseif table_at[i] then
      local t = table_at[i]
      table.insert(blocks, { kind = "table", line = i, header = t.header, rows = t.rows })
    elseif heading_at[i] then
      local h = heading_at[i]
      table.insert(blocks, { kind = "heading", line = i, level = h.level, title = M.plain(h.title) })
    elseif not skip[i] then
      table.insert(blocks, { kind = "line", line = i, text = M.plain(lines[i]) })
    end
  end
  return blocks
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

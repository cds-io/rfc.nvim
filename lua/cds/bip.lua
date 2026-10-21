-- Bitcoin improvement proposals, read: the preamble, the headings, code
-- and tables of a MediaWiki body, its footnotes, the proposals a line
-- names, and the repository's README as the index. A proposal written in
-- markdown shares the preamble and the mentions and leaves its body to
-- cds.eip. Plain lines in, plain tables out; nothing here names the editor.
local mentions = require("cds.mentions")

local M = {}

---@class cds.bip.Heading
---@field level integer   -- 1 for ==Title==, 2 for ===Title===, and so on
---@field title string    -- plain
---@field line integer

---@class cds.bip.Code
---@field first integer   -- the line with the opening tag
---@field last integer    -- the line with the closing tag, or the last line when unterminated
---@field lang string     -- <source lang="x">: x; <pre>: ""
---@field code string[]   -- the lines between the tags, text sharing a line with a tag included

---@class cds.bip.Table
---@field first integer
---@field last integer
---@field caption string|nil -- a |+ line, or a one-cell ! row spanning columns, before the rows
---@field header boolean  -- whether the first row's cells were written with !
---@field rows string[][] -- each row's cells, plain

---@class cds.bip.Note
---@field n integer
---@field text string     -- plain

---@class cds.bip.Mention
---@field kind "bip"
---@field id string|nil       -- the number without leading zeros; nil for a link into the document itself
---@field section string|nil  -- the anchor a link names, when it names one
---@field first integer       -- byte range of the text a link would replace
---@field last integer

---@class cds.bip.Block
---@field kind "heading"|"fence"|"table"|"notes"|"line"
---@field line integer
---@field level integer|nil    -- heading
---@field title string|nil     -- heading: plain
---@field lang string|nil      -- fence
---@field code string[]|nil    -- fence: as written
---@field caption string|nil   -- table
---@field header boolean|nil   -- table
---@field rows string[][]|nil  -- table: plain
---@field notes cds.bip.Note[]|nil  -- notes: every footnote of the text
---@field text string|nil      -- line: plain

---@class cds.bip.Entry
---@field id string
---@field title string
---@field status string
---@field type string
---@field layer string

---@param s string
---@return string
local function trim(s)
  return (s:match("^%s*(.-)%s*$"))
end

---@param code integer
---@return string
local function utf8_char(code)
  if code < 0x80 then
    return string.char(code)
  elseif code < 0x800 then
    return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
  elseif code < 0x10000 then
    return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
  end
  return string.char(
    0xF0 + math.floor(code / 0x40000),
    0x80 + math.floor(code / 0x1000) % 0x40,
    0x80 + math.floor(code / 0x40) % 0x40,
    0x80 + code % 0x40
  )
end

-- stylua: ignore
local ENTITIES = {
  amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " ",
  rarr = "→", larr = "←", le = "≤", ge = "≥", ne = "≠", times = "×", minus = "−",
  mdash = "—", ndash = "–", hellip = "…",
}

---@param s string
---@return string
local function unescape(s)
  return (
    s:gsub("&(#?%w+);", function(e)
      if ENTITIES[e] then
        return ENTITIES[e]
      end
      local n = e:match("^#(%d+)$")
      if n then
        return utf8_char(tonumber(n))
      end
      local hex = e:match("^#[xX](%x+)$")
      if hex then
        return utf8_char(tonumber(hex, 16))
      end
      return "&" .. e .. ";"
    end)
  )
end

--- Which markup the text is written in: MediaWiki when a line is a ==
--- heading (every such proposal has one), markdown otherwise.
---@param lines string[]
---@return "mediawiki"|"markdown"
function M.format(lines)
  for _, line in ipairs(lines) do
    if line:match("^==+[^=]") then
      return "mediawiki"
    end
  end
  return "markdown"
end

-- a key starts with a letter; a continued value may start with a date
local FIELD = "^%s+(%a[%w%-]*):%s*(.-)%s*$"

--- The preamble: the first <pre> block (a ``` fence in markdown) whose
--- lines are `  Key: value`, as a table keyed by the lowercased keys, with
--- the lines it spans. A value continued on deeper-indented lines is joined
--- with spaces. Without one the table is empty and the range nil.
---@param lines string[]
---@return table<string, string> fields
---@return integer|nil first
---@return integer|nil last
function M.preamble(lines)
  local i = 1
  while i <= #lines do
    local opener = lines[i]:match("^%s*<pre>%s*$") and "</pre>" or lines[i]:match("^%s*```%s*$") and "```" or nil
    if opener then
      local last = i + 1
      while last <= #lines and not lines[last]:match(opener, 1, true) do
        last = last + 1
      end
      if lines[i + 1] and lines[i + 1]:match(FIELD) then
        local fields, key = {}, nil
        for j = i + 1, math.min(last, #lines) - 1 do
          local k, v = lines[j]:match(FIELD)
          if k then
            key, fields[k:lower()] = k:lower(), v
          elseif key and lines[j]:match("^%s+%S") then
            fields[key] = fields[key] .. " " .. trim(lines[j])
          end
        end
        return fields, i, math.min(last, #lines)
      end
      i = last + 1
    else
      i = i + 1
    end
  end
  return {}, nil, nil
end

--- The code blocks: <pre> and <source lang="x">. A line that starts with
--- the opening tag opens one, text after the tag its first line; the line
--- holding the closing tag ends it, text before the tag its last; the tags
--- on one line are a one-line block. A block inside other text on its line
--- is a code span, not a block. An unterminated block runs to the end.
---@param lines string[]
---@return cds.bip.Code[]
function M.code(lines)
  local blocks = {}
  local i = 1
  while i <= #lines do
    local line = lines[i]
    local lang, rest = line:match('^%s*<source%s+lang="([^"]*)"%s*>(.*)$')
    local closer = lang and "</source>" or nil
    if not lang then
      rest = line:match("^%s*<pre>(.*)$")
      if rest then
        lang, closer = "", "</pre>"
      end
    end
    if closer then
      local code = {}
      local function open_line(text)
        if text ~= "" then
          table.insert(code, text)
        end
      end
      local before = rest:match("^(.-)" .. closer)
      if before then
        open_line(before)
        table.insert(blocks, { first = i, last = i, lang = lang, code = code })
        i = i + 1
      else
        open_line(rest)
        local last = i + 1
        while last <= #lines and not lines[last]:find(closer, 1, true) do
          table.insert(code, lines[last])
          last = last + 1
        end
        if last <= #lines then
          open_line(lines[last]:match("^(.-)" .. closer))
        else
          last = #lines
        end
        table.insert(blocks, { first = i, last = last, lang = lang, code = code })
        i = last + 1
      end
    else
      i = i + 1
    end
  end
  return blocks
end

---@param blocks { first: integer, last: integer }[]
---@return fun(i: integer): boolean
local function within(blocks)
  return function(i)
    for _, b in ipairs(blocks) do
      if i >= b.first and i <= b.last then
        return true
      end
    end
    return false
  end
end

--- The headings, outside code: ==Title== is level 1, each further sign one
--- deeper; the titles plain.
---@param lines string[]
---@return cds.bip.Heading[]
function M.headings(lines)
  local headings, inside = {}, within(M.code(lines))
  for i, line in ipairs(lines) do
    local signs, title = line:match("^(=+)%s*(.-)%s*=+%s*$")
    if signs and title ~= "" and not inside(i) then
      table.insert(headings, { level = math.max(#signs - 1, 1), title = M.plain(title), line = i })
    end
  end
  return headings
end

--- Every wiki link as its text: [[x|text]] is text, [[x]] is x, a file is
--- nothing.
---@param s string
---@return string
function M.unlink(s)
  return (
    s:gsub("%[%[([^%]]-)%]%]", function(inner)
      if inner:match("^File:") then
        return ""
      end
      return inner:match("^.*|(.-)$") or inner
    end)
  )
end

--- MediaWiki inline markup as plain text: bold and italic marks dropped,
--- <code>, <tt> and an inline <pre> as backticks, every other tag dropped
--- with its text kept, an external link as its text and address, a wiki
--- link to a proposal (or into the document) kept for the mention pass and
--- any other unwrapped, entities unescaped.
---@param s string
---@return string
function M.plain(s)
  local spans = {}
  local function keep(span)
    table.insert(spans, span)
    return "\1" .. #spans .. "\1"
  end
  s = s:gsub("`[^`]*`", keep)
  s = s:gsub("<code>(.-)</code>", function(x)
    return keep("`" .. x .. "`")
  end)
  s = s:gsub("<tt>(.-)</tt>", function(x)
    return keep("`" .. x .. "`")
  end)
  s = s:gsub("<pre>(.-)</pre>", function(x)
    return keep("`" .. x .. "`")
  end)
  s = s:gsub("%[%[([^%]]-)%]%]", function(inner)
    if inner:match("^bip%-%d+%.%a+") or inner:match("^#") then
      return "[[" .. inner .. "]]"
    end
    return M.unlink("[[" .. inner .. "]]")
  end)
  s = s:gsub("%[(https?://[^%s%]]+)%s+([^%]]+)%]", "%2 (%1)")
  s = s:gsub("%[(https?://[^%s%]]+)%]", "%1")
  s = s:gsub("'''", ""):gsub("''", "")
  s = s:gsub("</?%a[%w%-]*%s[^>]*>", ""):gsub("</?%a[%w%-]*/?>", "")
  s = unescape(s)
  return (s:gsub("\1(%d+)\1", function(n)
    return spans[tonumber(n)]
  end))
end

--- A row's cell: an attribute prefix (colspan=4|) dropped, the text plain
--- and unlinked.
---@param cell string
---@return string
local function plain_cell(cell)
  local text = cell:match("^[^|]*=[^|]*|(.*)$") or cell
  return trim(M.unlink(M.plain(text)))
end

--- Every wikitable ({| ... |}) as rows of plain cells: |- starts a row, a
--- ! line holds header cells split at !!, a | line cells split at ||; a
--- line without a mark continues the last cell. The caption is a |+ line,
--- or a ! row of one cell spanning columns, which the BIPs write instead.
---@param lines string[]
---@return cds.bip.Table[]
function M.tables(lines)
  local tables = {}
  local i = 1
  while i <= #lines do
    if lines[i]:match("^%s*{|") then
      local rows, row, first_row_marked, caption, spanning = {}, nil, nil, nil, false
      local function close_row()
        if row and #row == 1 and spanning and #rows == 0 then
          caption, first_row_marked = row[1], nil
        elseif row and #row > 0 then
          table.insert(rows, row)
        end
        row, spanning = nil, false
      end
      local function cells(text, sep, mark)
        row = row or {}
        if first_row_marked == nil then
          first_row_marked = mark
        end
        for cell in (text .. sep):gmatch("(.-)" .. sep) do
          table.insert(row, plain_cell(cell))
        end
      end
      local last = i + 1
      while last <= #lines and not lines[last]:match("^%s*|}") do
        local line = lines[last]
        if line:match("^%s*|%-") then
          close_row()
        elseif line:match("^%s*|%+") then
          caption = plain_cell(line:match("^%s*|%+(.*)$"))
        elseif line:match("^%s*!") then
          spanning = line:match("^%s*!%s*colspan") ~= nil
          cells(line:match("^%s*!(.*)$"), "!!", "!")
        elseif line:match("^%s*|") then
          cells(line:match("^%s*|(.*)$"), "||", "|")
        elseif row and #row > 0 and trim(line) ~= "" then
          row[#row] = row[#row] .. " " .. plain_cell(line)
        end
        last = last + 1
      end
      close_row()
      table.insert(tables, {
        first = i,
        last = math.min(last, #lines),
        caption = caption,
        header = first_row_marked == "!",
        rows = rows,
      })
      i = last + 1
    else
      i = i + 1
    end
  end
  return tables
end

--- The footnotes: every <ref>text</ref> replaced by its number in brackets
--- and collected, in order of first use; a named ref used again by
--- <ref name="x" /> keeps its number; a ref closed on a later line takes
--- the lines between into its text and leaves them empty. The notes' text
--- is plain.
---@param lines string[]
---@return string[] lines   -- the same count, markers in place of refs
---@return cds.bip.Note[] notes
function M.footnotes(lines)
  local out, notes, named = {}, {}, {}
  local open = nil
  local function note(name, text)
    local n = name and named[name]
    if not n then
      n = #notes + 1
      notes[n] = { n = n, text = trim(M.plain(trim(text))) }
      if name then
        named[name] = n
      end
    end
    return " [" .. n .. "]"
  end
  for i, line in ipairs(lines) do
    local done, rest = "", line
    if open then
      local before, after = rest:match("^(.-)</ref>(.*)$")
      if before then
        table.insert(open.parts, before)
        notes[open.n].text = trim(M.plain(trim(table.concat(open.parts, " "))))
        open, rest = nil, after
      else
        table.insert(open.parts, rest)
        rest = ""
      end
    end
    while rest ~= "" do
      -- <ref> or <ref name=...>; <references /> is no ref
      local s, e, attrs = rest:find("<ref(%s[^>]*)>")
      local bare_s, bare_e = rest:find("<ref>", 1, true)
      if bare_s and (not s or bare_s < s) then
        s, e, attrs = bare_s, bare_e, ""
      end
      if not s then
        break
      end
      local name = attrs:match('name%s*=%s*"([^"]*)"') or attrs:match("name%s*=%s*([^%s/]+)")
      done = done .. rest:sub(1, s - 1)
      if attrs:match("/%s*$") then
        done = done .. note(name, "")
        rest = rest:sub(e + 1)
      else
        local text, after = rest:sub(e + 1):match("^(.-)</ref>(.*)$")
        if text then
          done = done .. note(name, text)
          rest = after
        else
          done = done .. note(name, "")
          open = { n = #notes, parts = { rest:sub(e + 1) } }
          rest = ""
        end
      end
    end
    out[i] = done .. rest
  end
  return out, notes
end

---@param id string
---@return string
local function number(id)
  return (id:gsub("^0+(%d)", "%1"))
end

---@param id string
---@param section string|nil
---@return table
local function named(id, section)
  return { kind = "bip", id = number(id), section = section }
end

---@param section string
---@return table
local function own(section)
  return { kind = "bip", section = section }
end

--- Every proposal a line names, in order of position: a wiki link
--- ([[bip-0032.mediawiki|BIP 32]], with a section after #), a link into
--- the document itself ([[#anchor|text]]), a markdown link
--- ([BIP 2](bip-0002.mediawiki)), and a bare BIP 32, BIP-32, BIP-0032,
--- BIP32 or BIP0032 outside those. Numbers lose their leading zeros.
---@param line string
---@return cds.bip.Mention[]
function M.mentions(line)
  return mentions.scan(line, {
    { "%[%[bip%-(%d+)%.%a+#?([%w%-_]*)|[^%]]*%]%]", named },
    { "%[%[#([%w%-_]+)|[^%]]*%]%]", own },
    { "%[[^%]]*%]%(bip%-(%d+)%.%a+#?([%w%-_]*)%)", named },
  }, { "BIP[%- ]?0*(%d+)", named })
end

--- The body as blocks, every piece of text already plain: a heading, a
--- code block (as a fence, the shape a renderer folds over), a table, the
--- notes where <references /> stands, or one line. The footnotes are
--- replaced first, so a line carries its markers. Lines in `omit` (the
--- preamble) are left out.
---@param lines string[]
---@param omit? { first: integer, last: integer }
---@return cds.bip.Block[]
function M.blocks(lines, omit)
  local text, notes = M.footnotes(lines)
  local code_at, table_at, skip = {}, {}, {}
  for _, c in ipairs(M.code(text)) do
    code_at[c.first] = c
    for i = c.first, c.last do
      skip[i] = true
    end
  end
  for _, t in ipairs(M.tables(text)) do
    table_at[t.first] = t
    for i = t.first, t.last do
      skip[i] = true
    end
  end
  local heading_at = {}
  for _, h in ipairs(M.headings(text)) do
    heading_at[h.line] = h
  end
  local function block(i, line)
    if omit and i >= omit.first and i <= omit.last then
      return nil
    elseif code_at[i] then
      return { kind = "fence", line = i, lang = code_at[i].lang, code = code_at[i].code }
    elseif table_at[i] then
      local t = table_at[i]
      return { kind = "table", line = i, caption = t.caption, header = t.header, rows = t.rows }
    elseif heading_at[i] then
      return { kind = "heading", line = i, level = heading_at[i].level, title = heading_at[i].title }
    elseif line:match("^%s*<references%s*/>%s*$") then
      return { kind = "notes", line = i, notes = notes }
    elseif not skip[i] then
      return { kind = "line", line = i, text = M.plain(line) }
    end
  end
  local blocks = {}
  for i, line in ipairs(text) do
    local b = block(i, line)
    if b then
      table.insert(blocks, b)
    end
  end
  return blocks
end

--- The README's table as entries: a row starts with the link to the
--- proposal's file, and its next cells are the layer, title, owner, type
--- and status.
---@param lines string[]
---@return cds.bip.Entry[]
function M.index(lines)
  local entries, cells = {}, nil
  local FIELDS = { "layer", "title", "owner", "type", "status" }
  for _, line in ipairs(lines) do
    local id = line:match("^|%s*%[%[bip%-(%d+)%.%a+|")
    if id then
      cells = {}
      table.insert(entries, { id = number(id), title = "", status = "", type = "", layer = "" })
    elseif cells and line:match("^|%-") then
      cells = nil
    elseif cells and #cells < #FIELDS and line:match("^|") and not line:match("^|}") then
      table.insert(cells, plain_cell(line:match("^|%s*(.-)%s*$")))
      local field = FIELDS[#cells]
      if field ~= "owner" then
        entries[#entries][field] = cells[#cells]
      end
    end
  end
  return entries
end

return M

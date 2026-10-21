-- Solana improvement documents, read: the proposals a line names, the
-- proposals directory (as the GitHub contents API lists it) as the index,
-- and the list and number values a frontmatter carries. The body is
-- markdown with a YAML frontmatter, which cds.eip reads. Plain lines in,
-- plain tables out; nothing here names the editor.
local M = {}

---@class cds.simd.Mention
---@field kind "simd"
---@field id string          -- the number without leading zeros
---@field section string|nil -- the anchor a link names, when it names one
---@field first integer      -- byte range of the text a link would replace
---@field last integer

---@class cds.simd.Entry
---@field id string
---@field file string   -- 0064-transaction-receipt.md
---@field title string  -- the file's slug as words: Transaction Receipt

---@param id string
---@return string
local function number(id)
  return (id:gsub("^0+(%d)", "%1"))
end

--- The spans found so far blanked out of a line, so a scan for bare
--- mentions never reads a link's text, and every position still counts
--- from the line's start.
---@param line string
---@param found { first: integer, last: integer }[]
---@return string
local function without(line, found)
  for _, m in ipairs(found) do
    line = line:sub(1, m.first - 1) .. (" "):rep(m.last - m.first + 1) .. line:sub(m.last + 1)
  end
  return line
end

--- Every proposal a line names, in order of position: a markdown link to
--- a proposal's file (`./0033-slug.md`, or the repository's address for
--- it, with an anchor after #), the whole link; and a bare SIMD-0033,
--- SIMD-33, SIMD 0033 or SIMD 33 outside those. Numbers lose their
--- leading zeros.
---@param line string
---@return cds.simd.Mention[]
function M.mentions(line)
  local found = {}
  local function add(first, after, id, section)
    local m = { kind = "simd", id = number(id), first = first, last = after - 1 }
    if section and section ~= "" then
      m.section = section
    end
    table.insert(found, m)
  end
  local LINK = "%[[^%]]*%]%([^%)%s]-(%d%d%d%d)%-[%w%-%._]-%.md#?([%w%-_]*)%)"
  for first, id, section, after in line:gmatch("()" .. LINK .. "()") do
    add(first, after, id, section)
  end
  local bare = without(line, found)
  for first, id, after in bare:gmatch("()SIMD[%- ]?0*(%d+)()") do
    local before = bare:sub(first - 1, first - 1)
    local following = bare:sub(after, after)
    if not before:match("[%w%-]") and not following:match("%w") then
      add(first, after, id, nil)
    end
  end
  table.sort(found, function(a, b)
    return a.first < b.first
  end)
  return found
end

--- The proposals directory as entries: every `"name": "NNNN-slug.md"` in
--- the contents API's answer, the title read from the slug (a few slugs
--- join their words with underscores).
---@param lines string[]
---@return cds.simd.Entry[]
function M.index(lines)
  local entries = {}
  for _, line in ipairs(lines) do
    for id, slug in line:gmatch('"name"%s*:%s*"(%d%d%d%d)%-([%w%-%._]-)%.md"') do
      local title = slug:gsub("[%-_]", " "):gsub("(%a)([%w]*)", function(first, rest)
        return first:upper() .. rest
      end)
      table.insert(entries, { id = number(id), file = id .. "-" .. slug .. ".md", title = title })
    end
  end
  return entries
end

--- The items of a frontmatter list as cds.eip.frontmatter joins it
--- ("- A - B"), or of an inline value at its commas; none for nothing.
---@param value string|nil
---@return string[]
function M.list(value)
  local items = {}
  if not value or value == "" then
    return items
  end
  local sep = value:match("^%-%s") and "%s+%-%s+" or "%s*,%s*"
  value = value:gsub("^%-%s+", "")
  for item in (value .. (sep == "%s*,%s*" and "," or " - ")):gmatch("(.-)" .. sep) do
    if item ~= "" then
      table.insert(items, item)
    end
  end
  return items
end

--- The number a frontmatter value carries ('0064' is 64); nil when none.
---@param value string|nil
---@return string|nil
function M.number(value)
  local digits = value and value:match("(%d+)")
  return digits and number(digits) or nil
end

return M

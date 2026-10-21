-- Solana improvement documents, read: the proposals a line names, the
-- proposals directory (as the GitHub contents API lists it) as the index,
-- and the list and number values a frontmatter carries. The body is
-- markdown with a YAML frontmatter, which cds.eip reads. Plain lines in,
-- plain tables out; nothing here names the editor.
local mentions = require("cds.mentions")

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

---@param id string
---@param section string|nil
---@return table
local function named(id, section)
  return { kind = "simd", id = number(id), section = section }
end

--- Every proposal a line names, in order of position: a markdown link to
--- a proposal's file (`./0033-slug.md`, or the repository's address for
--- it, with an anchor after #), the whole link; and a bare SIMD-0033,
--- SIMD-33, SIMD 0033 or SIMD 33 outside those. Numbers lose their
--- leading zeros.
---@param line string
---@return cds.simd.Mention[]
function M.mentions(line)
  return mentions.scan(
    line,
    { { "%[[^%]]*%]%([^%)%s]-(%d%d%d%d)%-[%w%-%._]-%.md#?([%w%-_]*)%)", named } },
    { "SIMD[%- ]?0*(%d+)", named }
  )
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

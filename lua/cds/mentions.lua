-- The scan under the proposal readers' mentions: the links a line makes,
-- by their patterns, then the bare spellings outside them, in order of
-- position. A reader gives the forms (a pattern with captures, and what
-- the captures mean); the scan gives every mention its byte range, blanks
-- the links before the bare pass (so a link's text is found once and
-- every position still counts from the line's start), and sorts.
local M = {}

---@class cds.Mention
---@field kind string
---@field id string|nil       -- nil for a link into the document itself
---@field section string|nil  -- the anchor a link names, when it names one
---@field first integer       -- byte range of the text a link would replace
---@field last integer

---@class cds.MentionForm
---@field [1] string                        -- the pattern, with captures
---@field [2] fun(...: string): table|nil   -- the captures as kind, id, section; nil for no mention

---@param line string
---@param form cds.MentionForm
---@param add fun(first: integer, last: integer, fields: table)
local function each(line, form, add)
  local init = 1
  while init <= #line do
    local found = { line:find(form[1], init) }
    local first, last = found[1], found[2]
    if not first then
      break
    end
    local fields = form[2](unpack(found, 3))
    if fields then
      add(first, last, fields)
    end
    init = math.max(first, last) + 1
  end
end

--- Every mention a line makes: the links by their forms, then the bare
--- form outside them, where a bare match stands on its own (no letter,
--- digit or dash before it, no letter or digit after).
---@param line string
---@param links cds.MentionForm[]
---@param bare cds.MentionForm
---@return cds.Mention[]
function M.scan(line, links, bare)
  local found = {}
  local function add(first, last, fields)
    local m = { kind = fields.kind, id = fields.id, first = first, last = last }
    if fields.section and fields.section ~= "" then
      m.section = fields.section
    end
    table.insert(found, m)
  end
  for _, form in ipairs(links) do
    each(line, form, add)
  end
  local blank = line
  for _, m in ipairs(found) do
    blank = blank:sub(1, m.first - 1) .. (" "):rep(m.last - m.first + 1) .. blank:sub(m.last + 1)
  end
  each(blank, bare, function(first, last, fields)
    local before = blank:sub(first - 1, first - 1)
    local after = blank:sub(last + 1, last + 1)
    if not before:match("[%w%-]") and not after:match("%w") then
      add(first, last, fields)
    end
  end)
  table.sort(found, function(a, b)
    return a.first < b.first
  end)
  return found
end

return M

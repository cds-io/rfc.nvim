-- The outline of a rendered document: its section headings, which are the
-- lines that carry a section tag, with a level, and the questions the keys
-- and the sidebar ask of them. Plain lines in, plain tables out; nothing
-- here names the editor.
local M = {}

---@class rfc.Heading
---@field tag string      -- rfc9110-5.6.1, eip1559-abstract
---@field text string     -- the heading as written, its tag stripped: "5.6.1.  Lists"
---@field level integer   -- 1 for "1.", "Appendix A." and "Index"; the depth of 5.6.1 (3)
---@field line integer    -- the heading's line in the document

--- The number a heading starts with, as written: "5.6.1.", "Appendix A.",
--- "B.1.", "1"; nil for a title alone.
---@param text string
---@return string|nil
local function label(text)
    return text:match("^(Appendix%s+%u%.?)%s") or text:match("^(%u%.[%d%.]*%d%.?)%s") or text:match("^([%d%.]*%d%.?)%s")
end
M.label = label

--- How deep a number goes: "5.6.1." is 3, "Appendix A." is 1.
---@param num string
---@return integer
local function depth(num)
    local parts = 0
    for _ in num:gsub("^Appendix%s+", ""):gmatch("[^%.%s]+") do
        parts = parts + 1
    end
    return parts
end

--- A section tag ends the line: a source prefix, the number, a dash and
--- the section's name; the file tags and the reference entries' tags are
--- not sections.
---@param line string
---@return string|nil
local function section_tag(line)
    local tag = line:match("%*(%l%l%l%d+%-[%w%.%-]*)%*$")
    if tag and not tag:match("^%l+%d+%-ref%-") then
        return tag
    end
end

--- The headings of a rendered document, in order. A numbered heading's
--- level is its number's depth; any other's is read from its row in the
--- document's own table of contents, where the render indented it two
--- spaces per level, measured from the shallowest row; a heading no row
--- names is level 1.
---@param lines string[]
---@return rfc.Heading[]
function M.of(lines)
    local row_indent, shallowest = {}, nil
    for _, line in ipairs(lines) do
        local indent, tag = line:match("^(%s*)|(%l%l%l%d+%-[%w%.%-]*)|")
        if tag and not row_indent[tag] then
            row_indent[tag] = #indent
            shallowest = math.min(shallowest or #indent, #indent)
        end
    end
    local headings = {}
    for i, line in ipairs(lines) do
        local tag = i > 1 and section_tag(line) or nil
        if tag then
            local text = line:gsub("%s*%*[^*]+%*$", "")
            local num = label(text)
            local level = 1
            if num then
                level = depth(num)
            elseif row_indent[tag] then
                level = math.floor((row_indent[tag] - shallowest) / 2) + 1
            end
            table.insert(headings, { tag = tag, text = text, level = level, line = i })
        end
    end
    return headings
end

--- The index of the heading whose section holds `line`: the heading on
--- that line or the nearest above it; nil above the first.
---@param headings rfc.Heading[]
---@param line integer
---@return integer|nil
function M.at(headings, line)
    local found
    for i, h in ipairs(headings) do
        if h.line > line then
            break
        end
        found = i
    end
    return found
end

--- The index of the heading `count` headings past `line`: forward for a
--- positive count, back for a negative one, the last heading in that
--- direction when fewer remain, nil when none does.
---@param headings rfc.Heading[]
---@param line integer
---@param count integer
---@return integer|nil
function M.step(headings, line, count)
    if count == 0 then
        return nil
    end
    local here = M.at(headings, line) or 0
    if count > 0 then
        if here >= #headings then
            return nil
        end
        return math.min(here + count, #headings)
    end
    -- the headings strictly above the line: the one on it is not a step back
    local above = here - ((headings[here] and headings[here].line == line) and 1 or 0)
    if above == 0 then
        return nil
    end
    return math.max(above + count + 1, 1)
end

---@class rfc.OutlineRows
---@field lines string[]              -- one per heading, indented two spaces per level below the first
---@field labels table<integer, integer[]>  -- per row, the byte span {first, last} of its number, 0-based and end-exclusive; absent for a title alone

--- The sidebar's rows.
---@param headings rfc.Heading[]
---@return rfc.OutlineRows
function M.rows(headings)
    local lines, labels = {}, {}
    for i, h in ipairs(headings) do
        local indent = string.rep("  ", h.level - 1)
        lines[i] = indent .. h.text
        local num = label(h.text)
        if num then
            labels[i] = { #indent, #indent + #num }
        end
    end
    return { lines = lines, labels = labels }
end

return M

-- Locate RFC headings from contents grammar.
local grammar = require("rfc.source.rfc.rows")
local parse_row, row_title, heading_prefix = grammar.parse, grammar.title, grammar.heading
local M = {}

---@param s string
---@return string
local function trim(s)
    return (s:match("^%s*(.-)%s*$"))
end
-- The ToC header: "Contents" or "Table of Contents", in any case, alone on its line.
---@param lines string[]
---@return integer|nil
local function header_line(lines)
    for i, line in ipairs(lines) do
        local t = trim(line):lower()
        if t == "contents" or t == "table of contents" then
            return i
        end
    end
end
-- Page furniture lands inside a table of contents when it crosses a page: a
-- "[Page n]" footer, and the running header, which is the same text on every
-- page. The headers are found by that repetition: any non-blank line that
-- occurs three times or more in the text.
---@param lines string[]
---@return fun(line: string): boolean
local function furniture(lines)
    local seen = {}
    for _, line in ipairs(lines) do
        if line:match("%S") then
            seen[line] = (seen[line] or 0) + 1
        end
    end
    return function(line)
        return (seen[line] or 0) >= 3 or line:match("%[Page%s+%w+%]%s*$") ~= nil
    end
end

---@param line string
---@return boolean
local function has_page(line)
    return line:match("%s%d+$") ~= nil or line:match("%.%d+$") ~= nil
end

--- Reads the table of contents, each row with the line its heading sits on in
--- the body; empty when the text has none. The ToC ends where the first section
--- begins: the first line that reads as the first row's heading and is not a
--- row itself (no page number, a different indent). A row whose heading never
--- appears is left out.
---@param lines string[]
---@return rfc.source.rfc.Section[]
function M.contents(lines)
    local header = header_line(lines)
    if not header then
        return {}
    end
    local rows, top_indent, stop, last_row_at = {}, nil, nil, nil
    local is_furniture = furniture(lines)
    for i = header + 1, #lines do
        local line = lines[i]
        if
            rows[1]
            and trim(line):match(rows[1].heading)
            and not has_page(line)
            and #line:match("^%s*") ~= rows[1].indent
        then
            stop = i
            break
        end
        -- a page break inside the ToC is neither a row nor a wrapped title
        local row = not is_furniture(line) and parse_row(line, top_indent) or nil
        if row then
            top_indent = top_indent and math.min(top_indent, row.indent) or row.indent
            row.toc_line = i
            row.heading = heading_prefix(row)
            table.insert(rows, row)
            last_row_at = i
        elseif
            not is_furniture(line)
            and last_row_at == i - 1
            and line:match("%S")
            and #line:match("^%s*") > rows[#rows].indent
        then
            local last = rows[#rows]
            last.title = last.title .. " " .. row_title(trim(line))
            last.heading = heading_prefix(last)
            last_row_at = i
        end
    end
    -- Headings come in ToC order, so each search starts where the last one
    -- ended; a row whose heading is missing costs one pass to the end.
    local sections, from = {}, stop
    for _, row in ipairs(rows) do
        for i = from or (row.toc_line + 1), #lines do
            if trim(lines[i]):match(row.heading) then
                table.insert(sections, {
                    number = row.number,
                    label = row.label,
                    title = row.title,
                    line = i,
                    toc_line = row.toc_line,
                })
                from = i + 1
                break
            end
        end
    end
    return sections
end

return M

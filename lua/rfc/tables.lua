-- A rendered document's aligned tables, read back from its lines, and the
-- entry form the rich view lays a wide one out in: each row as its first
-- cell over the other cells as labelled lines. Plain lines in, plain
-- tables out; nothing here names the editor.
local help_w3c = require("rfc.help_w3c")
local fp = require("cds.fp")

local M = {}

---@class rfc.Table
---@field caption_line integer   -- the `Table … ~` line
---@field first integer          -- the first row line (the header row when there is one)
---@field last integer           -- the last row line
---@field header string[]|nil    -- the header row's cells, when a rule line follows it
---@field rows string[][]        -- the other rows' cells

--- The column starts of a block of aligned rows: column 3 (after the two-
--- space indent), and every position that every row reaches only through
--- two spaces of gutter and some row fills.
---@param rows string[]
---@return integer[]
local function columns(rows)
    local width = 0
    for _, r in ipairs(rows) do
        width = math.max(width, #r)
    end
    local starts = { 3 }
    for i = 5, width do
        local gutter = fp.all(rows, function(r)
            return r:sub(i - 2, i - 1):match("^%s*$") ~= nil
        end)
        local filled = fp.any(rows, function(r)
            return r:sub(i, i):match("%S") ~= nil
        end)
        if gutter and filled then
            table.insert(starts, i)
        end
    end
    return starts
end

--- A row's cells by the column starts, each trimmed at its ends.
---@param row string
---@param starts integer[]
---@return string[]
local function cells(row, starts)
    return fp.map(starts, function(from, c)
        local to = starts[c + 1] and (starts[c + 1] - 1) or #row
        return (row:sub(from, to):gsub("^%s+", ""):gsub("%s+$", ""))
    end)
end

--- The tables of a rendered document: a `Table … ~` line, then the rows
--- indented two, up to the next blank line.
---@param lines string[]
---@return rfc.Table[]
function M.of(lines)
    local out = {}
    local i = 1
    while i <= #lines do
        if lines[i]:match("^Table.* ~$") or lines[i] == "Table ~" then
            local first = i + 1
            local last = first - 1
            while lines[last + 1] and lines[last + 1]:match("^  %S") do
                last = last + 1
            end
            if last >= first then
                local block = { unpack(lines, first, last) }
                local starts = columns(block)
                local header, rows = nil, {}
                local from = 1
                if block[2] and block[2]:match("^  [%-%s]+$") then
                    header = cells(block[1], starts)
                    from = 3
                end
                for r = from, #block do
                    table.insert(rows, cells(block[r], starts))
                end
                table.insert(out, { caption_line = i, first = first, last = last, header = header, rows = rows })
            end
            i = last + 1
        else
            i = i + 1
        end
    end
    return out
end

--- The entry form: each row's first cell on its own line, then its other
--- cells as `Label: text` lines wrapped and indented four, the label the
--- header's or the column's number.
---@param t { header?: string[], rows: string[][] }
---@param width integer
---@return string[]
function M.entries(t, width)
    local out = {}
    for _, row in ipairs(t.rows) do
        table.insert(out, row[1] or "")
        for c = 2, #row do
            local label = t.header and t.header[c] or tostring(c)
            for _, l in ipairs(help_w3c.wrap(label .. ": " .. row[c], "    ", width)) do
                table.insert(out, l)
            end
        end
    end
    return out
end

return M

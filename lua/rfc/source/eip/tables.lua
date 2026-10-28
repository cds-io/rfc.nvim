-- Markdown and HTML proposal tables.
local plain = require("rfc.source.eip.inline").plain
local trim = function(s)
    return (s:match("^%s*(.-)%s*$"))
end
local M = {}

--- Splits a pipe table's row into cells: the text between the bars, trimmed and
--- plain.
---@param line string
---@return string[]
local function pipe_cells(line)
    local cells = {}
    for cell in line:gsub("^%s*|", ""):gsub("|%s*$", ""):gmatch("[^|]+") do
        table.insert(cells, trim(plain(cell)))
    end
    return cells
end

--- Reads every table in the text as rows of plain-text cells, whether HTML
--- (<table>...</table>, as pandoc writes them) or markdown (a row of bars, then
--- the |---|---| rule, then rows).
---@param lines string[]
---@return rfc.source.eip.Table[]
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
                    table.insert(cells, trim(plain((cell:gsub("\n", " ")))))
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

return M

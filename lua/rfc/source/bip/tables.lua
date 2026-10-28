-- MediaWiki tables and README entries.
local inline = require("rfc.source.bip.inline")
local plain_cell = inline.cell
local trim = function(s)
    return (s:match("^%s*(.-)%s*$"))
end
local M = {}

--- Reads every wikitable ({| ... |}) as rows of plain cells: |- starts a row, a
--- ! line holds header cells split at !!, a | line holds cells split at ||, and
--- a line without a mark continues the last cell. The caption is a |+ line, or
--- a ! row of one cell spanning the columns, which the BIPs write instead.
---@param lines string[]
---@return rfc.source.bip.Table[]
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
---@param id string
---@return string
local function number(id)
    return (id:gsub("^0+(%d)", "%1"))
end
--- Reads the README's table as entries: a row starts with the link to the
--- proposal's file, and its next cells are the layer, title, owner, type and
--- status.
---@param lines string[]
---@return rfc.source.bip.Entry[]
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

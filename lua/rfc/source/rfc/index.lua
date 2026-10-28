-- RFC Editor index records.
local M = {}

---@param s string
---@return string
local function trim(s)
    return (s:match("^%s*(.-)%s*$"))
end
--- Reads the RFC Editor's index (rfc-index.txt) as entries. A block is a number
--- at column 0 and the indented lines that follow it; "Not Issued" numbers are
--- left out.
---@param lines string[]
---@return rfc.source.rfc.IndexEntry[]
function M.index(lines)
    local entries = {}
    local block
    local function close()
        if not block then
            return
        end
        local number, text = block.number, block.text
        block = nil
        if text:match("^Not Issued") then
            return
        end
        local formats = {}
        for format in (text:match("%(Format:%s*(.-)%)") or ""):gmatch("[^,%s]+") do
            table.insert(formats, format)
        end
        table.insert(entries, {
            number = number,
            label = text:match("^(.-%u%l+ %d%d%d%d%.)") or (text:match("^(.-)%s*%(") or text),
            obsoletes = text:match("%(Obsoletes%s+(.-)%)"),
            obsoleted_by = text:match("%(Obsoleted by%s+(.-)%)"),
            formats = formats,
            status = text:match("%(Status:%s*(.-)%)"),
        })
    end
    for _, line in ipairs(lines) do
        local number, text = line:match("^(%d+)%s+(%S.*)$")
        if number then
            close()
            block = { number = number, text = trim(text) }
        elseif block and line:match("^%s+%S") then
            block.text = block.text .. " " .. trim(line)
        elseif block then
            close()
        end
    end
    close()
    return entries
end

return M

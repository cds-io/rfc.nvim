-- The texts the cds.rfc spec reads: five RFCs and an excerpt of the RFC
-- index, fetched from the RFC Editor (https://www.rfc-editor.org/rfc/rfcN.txt
-- and /rfc-index.txt) on 2026-10-19, with form feeds and the byte-order mark
-- removed, which is how a plugin stores a fetched text. The excerpt is the
-- index's header and the blocks for RFCs 14, 31, 61, 266 and 2616.
-- Resolved from this file's own directory so a spec runs from any working
-- directory. This file copies with lua/cds/rfc.lua and spec/cds/rfc_spec.lua.
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."

local M = {
    rfc791 = "rfc791.txt",
    rfc1945 = "rfc1945.txt",
    rfc2616 = "rfc2616.txt",
    rfc3986 = "rfc3986.txt",
    rfc9110 = "rfc9110.txt",
    rfc_index = "rfc-index.txt",
}

M.dir = here .. "/fixtures/"

---@param name string
---@return string[]
function M.read(name)
    local lines = {}
    for line in io.lines(M.dir .. name) do
        table.insert(lines, line)
    end
    return lines
end

--- The first entry whose `field` equals `value`.
---@generic T
---@param entries T[]
---@param field string
---@param value any
---@return T|nil
function M.find(entries, field, value)
    for _, e in ipairs(entries) do
        if e[field] == value then
            return e
        end
    end
end

return M

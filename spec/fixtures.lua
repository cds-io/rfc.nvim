-- The RFC texts the plugin's specs read: the same five RFCs and index
-- excerpt the cds.rfc spec uses in ../cds (fetched from the RFC Editor,
-- form feeds and the byte-order mark removed, as a fetched text is stored).
-- Resolved from this file's own directory so a spec runs from any working
-- directory (the nlua run starts busted twice).
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."

local M = {
    rfc791 = "rfc791.txt",
    rfc1945 = "rfc1945.txt",
    rfc2616 = "rfc2616.txt",
    rfc3986 = "rfc3986.txt",
    rfc9110 = "rfc9110.txt",
    rfc_index = "rfc-index.txt",
}

---@param name string
---@return string[]
function M.read(name)
    local lines = {}
    for line in io.lines(here .. "/fixtures/" .. name) do
        table.insert(lines, line)
    end
    return lines
end

return M

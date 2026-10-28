-- Finds the reports a line cites. A CRS report cites another in prose, with
-- no link: "CRS Report R43397, Legislative Branch Appropriations", "CRS In
-- Focus IF12345", "CRS Insight IN11374", "CRS Legal Sidebar LSB11340", and
-- for the 1990s series "CRS Report 97-1011". The product word is often
-- "Report" whatever the series ("CRS Report IF12345"), so each form accepts
-- any lettered number after it; a bare number with no "CRS" before it is
-- not a mention, since public laws and sections look the same.
local mentions = require("rfc.source.mentions")

---@class rfc.source.crs.mentions
local M = {}

---@param id string
---@return table
local function named(id)
    return { kind = "crs", id = id:lower() }
end

-- Each form is one bare form for rfc.source.mentions.scan: the citation's
-- whole text is the mention, so a renderer replaces all of it with the tag.
local FORMS = {
    { "CRS Report (%u%u?%u?%d%d%d%d+)", named },
    { "CRS Report (%d%d%-%d%d%d%d?)", named },
    { "CRS In Focus (IF%d%d%d%d+)", named },
    { "CRS Insight (IN%d%d%d%d+)", named },
    { "CRS Legal Sidebar (LSB%d%d%d%d+)", named },
}

--- Every report a line cites, in order of position; the id lowercased, as
--- the tag spells it.
---@param line string
---@return rfc.source.Mention[]
function M.mentions(line)
    local found = {}
    for _, form in ipairs(FORMS) do
        for _, m in ipairs(mentions.scan(line, {}, form)) do
            table.insert(found, m)
        end
    end
    table.sort(found, function(a, b)
        return a.first < b.first
    end)
    return found
end

return M

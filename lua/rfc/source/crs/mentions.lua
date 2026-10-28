-- Finds the reports a line cites. A CRS report cites another in prose, with
-- no link: "CRS Report R43397, Legislative Branch Appropriations", "CRS In
-- Focus IF12345", "CRS Insight IN11374", "CRS Legal Sidebar LSB11340", and
-- for the 1990s series "CRS Report 97-1011". The product word is often
-- "Report" whatever the series ("CRS Report IF12345"), so each form accepts
-- any lettered number after it; a bare number with no "CRS" before it is
-- not a mention, since public laws and sections look the same. `link_citations`
-- rewrites a report's HTML so each citation links to its tag, which the
-- normalization runs as one of its passes.
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
-- A number may end in letters: the 1990s series carried the division
-- (98-446RSH), and the IP series a letter (IP0333A).
local FORMS = {
    { "CRS Report (%u%u?%u?%d%d%d%d+%u?)", named },
    { "CRS Report (%d%d%-%d%d%d%d?%u*)", named },
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

--- A citation's link.
---@param id string
---@return string
local function tag_href(id)
    return 'href="rfc-tag:crs-' .. id .. '"'
end

--- Each citation linked to its tag. A citation in plain text is wrapped in
--- a link; one already inside a link that has no destination (pymupdf
--- wraps a PDF link as `<a><span>…</span></a>`) puts the tag on that link
--- instead, so links never nest; one inside a link with a destination is
--- left as it is.
---@param text string
---@return string
function M.link_citations(text)
    local out, pos = {}, 1
    local open_a, has_href = nil, false
    local function run(s)
        local found = M.mentions(s)
        if #found == 0 or (open_a and has_href) then
            table.insert(out, s)
        elseif open_a then
            out[open_a] = out[open_a]:gsub("^<a", "<a " .. tag_href(found[1].id), 1)
            has_href = true
            table.insert(out, s)
        else
            for i = #found, 1, -1 do
                local m = found[i]
                s = s:sub(1, m.first - 1)
                    .. "<a "
                    .. tag_href(m.id)
                    .. ">"
                    .. s:sub(m.first, m.last)
                    .. "</a>"
                    .. s:sub(m.last + 1)
            end
            table.insert(out, s)
        end
    end
    while pos <= #text do
        local lt = text:find("<", pos, true)
        if not lt then
            run(text:sub(pos))
            break
        end
        if lt > pos then
            run(text:sub(pos, lt - 1))
        end
        local gt = text:find(">", lt, true) or #text
        local tag = text:sub(lt, gt)
        if tag:match("^<a[%s>]") then
            open_a, has_href = #out + 1, tag:find("href=", 1, true) ~= nil
        elseif tag:match("^</a>") then
            open_a = nil
        end
        table.insert(out, tag)
        pos = gt + 1
    end
    return table.concat(out)
end

return M

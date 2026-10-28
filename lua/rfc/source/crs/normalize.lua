-- Rewrites a report's HTML, as EveryCRSReport.com renders it from the PDF,
-- into the shape the shared readers (rfc.source.html for the help view,
-- cds.html for the Markdown document) render well. Both read headings by
-- their `id`; the report has none, and carries its anchors as runs of
-- `<a name="_Toc…">` before or inside each heading instead. Its header
-- (`div.ReportHeader`: the title, "Updated <date> (<number>)", a jump link)
-- and its Contents, Figures and Tables lists duplicate what rfc.nvim builds
-- from the headings. Its citations are prose with no link. So, in order: the
-- header is read into the head and removed with the lists; a heading takes
-- its first anchor as its id; every other named anchor becomes an id; a
-- footnote mark reads as [n]; a citation becomes a link on the plugin's own
-- rfc-tag: scheme, which both readers follow; an empty image goes. Pure over
-- the text, so the model builder runs it on every render.
local mentions = require("rfc.source.crs.mentions")
local html = require("rfc.source.html")

---@class rfc.source.crs.normalize
local M = {}

---@class rfc.source.crs.Head
---@field title string     -- "" when the header is absent
---@field updated string   -- the header's line without the number: "Updated October 27, 2026"
---@field number string    -- R43397

--- The end of the `<div …>` opening at `open`, by div depth.
---@param text string
---@param open integer
---@return integer|nil
local function div_end(text, open)
    local depth, pos = 0, open
    while true do
        local first, last, close = text:find("<(/?)div[^>]*>", pos)
        if not first then
            return nil
        end
        depth = depth + (close == "/" and -1 or 1)
        if depth == 0 then
            return last
        end
        pos = last + 1
    end
end

--- Reads the header into the head and removes it with the `<hr>` after it.
---@param text string
---@return string
---@return rfc.source.crs.Head
local function header(text)
    local head = { title = "", updated = "", number = "" }
    local open = text:find('<div class="ReportHeader">', 1, true)
    if not open then
        return text, head
    end
    local close = div_end(text, open)
    if not close then
        return text, head
    end
    local block = text:sub(open, close)
    head.title = html.decode(html.squash(block:match("<h1>(.-)</h1>") or ""))
    local line = block:match("</h1>%s*<div>(.-)<br>") or ""
    head.number = line:match("%(([^()]+)%)%s*$") or ""
    head.updated = html.squash((line:gsub("%(([^()]+)%)%s*$", "")))
    local rest = text:sub(close + 1):gsub("^%s*<hr>", "")
    return text:sub(1, open - 1) .. rest, head
end

--- Removes the Contents, Figures and Tables headings with their lists.
---@param text string
---@return string
local function contents(text)
    for _, name in ipairs({ "Contents", "Figures", "Tables" }) do
        text = text:gsub("<h2>" .. name .. "</h2>%s*<ul>.-</ul>", "")
    end
    return text
end

local ANCHOR = '<a name="[^"]*"></a>'

--- A heading takes an id from its anchors: the one directly before it
--- (across a `<div>`), or the first of the run inside it, which moves out
--- in front of the heading, one anchor a pass, so every anchor stays a
--- target for the report's own links. A Word bookmark left mid-heading goes;
--- nothing links to one. A heading left without an id gets a numbered one,
--- so both readers anchor every heading.
---@param text string
---@return string
local function heading_ids(text)
    text = text:gsub('<a name="([^"]*)"></a>(%s*<div>%s*)<h(%d)>', function(name, between, level)
        return '<a name="' .. name .. '"></a>' .. between .. "<h" .. level .. ' id="' .. name .. '">'
    end)
    text = text:gsub("<h(%d)>(" .. ANCHOR .. ")", function(level, anchor)
        return anchor .. "<h" .. level .. ' id="' .. anchor:match('name="([^"]*)"') .. '">'
    end)
    local moved = 1
    while moved > 0 do
        text, moved = text:gsub('(<h%d id="[^"]*">)(' .. ANCHOR .. ")", "%2%1")
    end
    text = text:gsub('<a name="_Hlk[^"]*"></a>', "")
    local n = 0
    return (
        text:gsub("<h(%d)>", function(level)
            n = n + 1
            return "<h" .. level .. ' id="crs-h' .. n .. '">'
        end)
    )
end

--- Every remaining named anchor becomes an id.
---@param text string
---@return string
local function anchors(text)
    return (text:gsub('<a( [^>]-)name="', '<a%1id="'))
end

--- A footnote mark's number in brackets.
---@param text string
---@return string
local function footnotes(text)
    return (text:gsub('(<sup><a href="#fn%d+" id="ifn%d+">)(%d+)(</a></sup>)', "%1[%2]%3"))
end

--- The report normalized, and its head read from the header before the
--- header went.
---@param lines string[]
---@return string[]
---@return rfc.source.crs.Head
function M.normalize(lines)
    local text, head = header(table.concat(lines, "\n"))
    text = contents(text)
    text = heading_ids(text)
    text = anchors(text)
    text = footnotes(text)
    text = mentions.link_citations(text)
    text = text:gsub("<img>", "")
    local out = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        table.insert(out, line)
    end
    return out, head
end

return M

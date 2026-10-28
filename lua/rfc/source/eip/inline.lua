-- Proposal inline text, references and index listings.
local mentions = require("rfc.source.mentions")
local M = {}

---@param s string
---@return string
local function trim(s)
    return (s:match("^%s*(.-)%s*$"))
end
--- Reads the numbers a `requires:` field names: "155, 2718" gives { "155",
--- "2718" }.
---@param fields table<string, string>
---@return string[]
function M.requires(fields)
    local ids = {}
    for id in (fields.requires or ""):gmatch("%d+") do
        table.insert(ids, id)
    end
    return ids
end

local LINK = "%[(E[IR][PC])%-(%d+)%]%(%./[%w%-/%.]+%)"

---@param kind string
---@param id string
---@return table
local function named(kind, id)
    return { kind = kind:lower(), id = id }
end

--- Finds every EIP or ERC a line mentions, in order of position: a markdown
--- link whose text names one ("[EIP-2718](./eip-2718.md)", the whole link) and
--- a bare "EIP-155" or "ERC-20". The kind is the one the text uses.
---@param line string
---@return rfc.source.eip.Mention[]
function M.mentions(line)
    return mentions.scan(line, { { LINK, named } }, { "(E[IR][PC])%-(%d+)", named })
end

local ENTITIES =
    { ["&amp;"] = "&", ["&lt;"] = "<", ["&gt;"] = ">", ["&quot;"] = '"', ["&#39;"] = "'", ["&nbsp;"] = " " }

---@param s string
---@return string
local function unescape(s)
    return (s:gsub("&[%w#]+;", function(e)
        return ENTITIES[e] or e
    end))
end

--- Turns markdown inline markup and inline HTML into plain text: tags are
--- dropped (a <code> span becomes backticks), entities unescaped, **bold** and
--- *em* reduced to their text. A code span is kept as written, and so is an
--- autolink (<https://...>), which is no tag.
---@param s string
---@return string
function M.plain(s)
    local spans = {}
    s = s:gsub("`[^`]*`", function(span)
        table.insert(spans, span)
        return "\1" .. #spans .. "\1"
    end)
    s = s:gsub("<code>(.-)</code>", "`%1`")
    s = s:gsub("</?%a[%w%-]*%s[^>]*>", ""):gsub("</?%a[%w%-]*/?>", "")
    s = unescape(s)
    s = s:gsub("%*%*([^*]-)%*%*", "%1")
    s = s:gsub("%*([^%s*][^*]-)%*", "%1")
    return (s:gsub("\1(%d+)\1", function(n)
        return spans[tonumber(n)]
    end))
end
--- Reads the listing page as entries: each table row's number and title, under
--- the status heading the row sits beneath and the category the page's title
--- names (a category page reads "Core"; the all page reads "All").
---@param lines string[]
---@return rfc.source.eip.Entry[]
function M.listing(lines)
    local entries, status, category, entry = {}, "", "", nil
    for _, line in ipairs(lines) do
        local page = line:match('<h1 class="post%-title">(.-)</h1>')
        if page then
            category = trim(unescape(page))
        end
        local heading = line:match("<h2 [^>]*>(.-)</h2>")
        if heading then
            status = trim(unescape(heading))
        end
        local id = line:match('class="eipnum"><a [^>]*>(%d+)</a>')
        if id then
            entry = { id = id, title = "", status = status, category = category }
            table.insert(entries, entry)
        end
        local title = entry and line:match('class="title">(.-)</td>')
        if title then
            entry.title = trim(unescape((title:gsub("<[^>]->", ""))))
        end
    end
    return entries
end

return M

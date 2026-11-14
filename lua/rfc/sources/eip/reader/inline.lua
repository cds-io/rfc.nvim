-- An EIP's references and the index listings.
local mentions = require("rfc.source.mentions")
local unescape = require("rfc.format.proposal.markdown.inline").unescape
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
---@return rfc.sources.eip.reader.Mention[]
function M.mentions(line)
    return mentions.scan(line, { { LINK, named } }, { "(E[IR][PC])%-(%d+)", named })
end

--- Reads the listing page as entries: each table row's number and title, under
--- the status heading the row sits beneath and the category the page's title
--- names (a category page reads "Core"; the all page reads "All").
---@param lines string[]
---@return rfc.sources.eip.reader.Entry[]
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

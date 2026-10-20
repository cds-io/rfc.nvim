-- The sources a document can come from. Each is one record the rims read
-- without knowing which they hold: where its text and its index come from,
-- how its index reads, and how its text renders. The RFC Editor is one;
-- Ethereum's proposals are the other, over two repositories that share one
-- number space (ERC-20 is EIP-20), so the reader never has to say which.
local fetch = require("rfc.fetch")
local help = require("rfc.help")
local help_eip = require("rfc.help_eip")
local rfc = require("cds.rfc")
local eip = require("cds.eip")
local Task = require("cds.task")

local M = {}

---@class rfc.Entry
---@field id string
---@field label string      -- what the picker shows after the tag
---@field text boolean      -- whether the source has a text to render (an RFC published as PDF only has none)

---@class rfc.Source
---@field prefix string     -- the tag prefix: rfc, eip
---@field aliases string[]  -- other prefixes whose tags this source answers: erc for eip
---@field label string      -- how a message names it: RFC, EIP
---@field raw_ext string    -- the extension the fetched text is stored under
---@field index_file string -- the cache file the index is stored as
---@field fetch fun(id: string): cds.Task          -- of the text as one string
---@field index fun(): cds.Task                    -- of the index text as one string
---@field entries fun(lines: string[]): rfc.Entry[]  -- pure
---@field render fun(id: string, lines: string[]): rfc.HelpDoc  -- pure, total
---@field placeholder nil|fun(lines: string[]): boolean  -- pure: whether a stored text stands in for the document rather than being it

---@type rfc.Source
M.rfc = {
    prefix = "rfc",
    aliases = {},
    label = "RFC",
    raw_ext = "txt",
    index_file = "rfc-index.txt",
    fetch = function(id)
        return fetch.rfc(id)
    end,
    index = function()
        return fetch.index()
    end,
    entries = function(lines)
        local entries = {}
        for _, e in ipairs(rfc.index(lines)) do
            local text = false
            for _, f in ipairs(e.formats) do
                text = text or f == "TXT"
            end
            table.insert(entries, { id = e.number, label = e.label, text = text })
        end
        return entries
    end,
    render = help.render,
}

local EIPS = { repo = "ethereum/EIPs", dir = "EIPS", prefix = "eip", site = "https://eips.ethereum.org/all" }
local ERCS = { repo = "ethereum/ERCs", dir = "ERCS", prefix = "erc", site = "https://ercs.ethereum.org/all" }

--- Whether a text is the stub the EIPs repository leaves behind when a
--- proposal moves to the ERCs repository.
---@param lines string[]
---@return boolean
local function moved(lines)
    return eip.frontmatter(lines).status == "Moved"
end

---@type rfc.Source
M.eip = {
    prefix = "eip",
    aliases = { "erc" },
    label = "EIP",
    raw_ext = "md",
    index_file = "eip-index.html",
    -- the EIPs repository first; a moved stub means the text lives in ERCs
    fetch = function(id)
        return fetch.proposal(EIPS.repo, EIPS.dir, EIPS.prefix, id):bind(function(text)
            if moved(help.clean(text)) then
                return fetch.proposal(ERCS.repo, ERCS.dir, ERCS.prefix, id)
            end
            return Task.of(text)
        end)
    end,
    -- a stub stored by a fetch that did not yet follow the move is no text to
    -- render again; the document is fetched
    placeholder = moved,
    -- both listing pages, one after the other, as one text
    index = function()
        return Task.all({
            fetch.listing(EIPS.site, "the EIP listing"),
            fetch.listing(ERCS.site, "the ERC listing"),
        }):map(function(pages)
            return table.concat(pages, "\n")
        end)
    end,
    -- a number listed on both pages is one proposal; the first listing wins
    entries = function(lines)
        local entries, seen = {}, {}
        for _, e in ipairs(eip.listing(lines)) do
            if not seen[e.id] then
                seen[e.id] = true
                table.insert(entries, { id = e.id, label = e.title .. " (" .. e.status .. ")", text = true })
            end
        end
        return entries
    end,
    render = help_eip.render,
}

--- Every source, in the order the pickers list them.
M.all = { M.rfc, M.eip }

--- The source a tag belongs to, by its prefix or one of the aliases, or nil.
---@param tag string
---@return rfc.Source|nil
function M.of(tag)
    local prefix = tag:match("^(%l+)%d")
    if not prefix then
        return nil
    end
    for _, source in ipairs(M.all) do
        if source.prefix == prefix or vim.tbl_contains(source.aliases, prefix) then
            return source
        end
    end
end

return M

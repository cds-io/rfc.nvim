-- The sources a document can come from. Each is one record the rims read
-- without knowing which they hold: where its text and its index come from,
-- how its index reads, and how its text renders. The RFC Editor is one;
-- the two Ethereum repositories are the other two, from one constructor,
-- since both are a markdown file in a repository plus a listing page.
local fetch = require("rfc.fetch")
local help = require("rfc.help")
local help_eip = require("rfc.help_eip")
local rfc = require("cds.rfc")
local eip = require("cds.eip")

local M = {}

---@class rfc.Entry
---@field id string
---@field label string      -- what the picker shows after the number
---@field text boolean      -- whether the source has a text to render (an RFC published as PDF only has none)

---@class rfc.Source
---@field prefix string     -- the tag prefix: rfc, eip, erc
---@field label string      -- how a message names it: RFC, EIP, ERC
---@field raw_ext string    -- the extension the fetched text is stored under
---@field index_file string -- the cache file the index is stored as
---@field fetch fun(id: string): cds.Task          -- of the text as one string
---@field index fun(): cds.Task                    -- of the index text as one string
---@field entries fun(lines: string[]): rfc.Entry[]  -- pure
---@field render fun(id: string, lines: string[]): rfc.HelpDoc  -- pure, total

---@type rfc.Source
M.rfc = {
    prefix = "rfc",
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

---@param opts { prefix: string, label: string, repo: string, dir: string, site: string }
---@return rfc.Source
local function proposals(opts)
    return {
        prefix = opts.prefix,
        label = opts.label,
        raw_ext = "md",
        index_file = opts.prefix .. "-index.html",
        fetch = function(id)
            return fetch.proposal(opts.repo, opts.dir, opts.prefix, id)
        end,
        index = function()
            return fetch.listing(opts.site, "the " .. opts.label .. " listing")
        end,
        entries = function(lines)
            local entries = {}
            for _, e in ipairs(eip.listing(lines)) do
                table.insert(entries, { id = e.id, label = e.title .. " (" .. e.status .. ")", text = true })
            end
            return entries
        end,
        render = function(id, lines)
            return help_eip.render(opts.prefix, id, lines)
        end,
    }
end

M.eip = proposals({
    prefix = "eip",
    label = "EIP",
    repo = "ethereum/EIPs",
    dir = "EIPS",
    site = "https://eips.ethereum.org/all",
})

M.erc = proposals({
    prefix = "erc",
    label = "ERC",
    repo = "ethereum/ERCs",
    dir = "ERCS",
    site = "https://ercs.ethereum.org/all",
})

--- Every source, in the order the picker lists them.
M.all = { M.rfc, M.eip, M.erc }

--- The source a tag belongs to, by its prefix, or nil.
---@param tag string
---@return rfc.Source|nil
function M.of(tag)
    local prefix = tag:match("^(%l+)%d")
    return prefix and M[prefix] or nil
end

return M

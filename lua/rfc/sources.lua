-- The sources a document can come from. Each is one record the rims read
-- without knowing which they hold: where its text and its index come from,
-- how its index reads, and how its text renders. The RFC Editor is one;
-- Ethereum's proposals are another, over two repositories that share one
-- number space (ERC-20 is EIP-20), so the reader never has to say which;
-- Bitcoin's proposals are the third and Solana's the fourth.
local fetch = require("rfc.fetch")
local help = require("rfc.help")
local help_eip = require("rfc.help_eip")
local help_bip = require("rfc.help_bip")
local help_simd = require("rfc.help_simd")
local rfc = require("cds.rfc")
local eip = require("cds.eip")
local bip = require("cds.bip")
local simd = require("cds.simd")
local subjects = require("cds.subjects")
local Task = require("cds.task")
local fp = require("cds.fp")

local M = {}

---@class rfc.Entry
---@field id string
---@field label string      -- what the picker shows after the tag
---@field text boolean      -- whether the source has a text to render (an RFC published as PDF only has none)

---@class rfc.Subjects
---@field index_file string   -- the cache file the subjects index is stored as; the source's own index file when the index carries the subjects
---@field index fun(): cds.Task   -- of the index text as one string
---@field entries fun(lines: string[]): cds.subjects.Entry[]|nil, string|nil  -- pure
---@field title string        -- the document's title: RFCs by subject
---@field about string        -- the line naming the data

---@class rfc.Source
---@field prefix string     -- the tag prefix: rfc, eip
---@field aliases string[]  -- other prefixes whose tags this source answers: erc for eip
---@field label string      -- how a message names it: RFC, EIP
---@field raw_ext string    -- the extension the fetched text is stored under
---@field index_file string -- the cache file the index is stored as
---@field fetch fun(id: string, file?: string): cds.Task  -- of the text as one string; `file` is what locate found
---@field locate nil|fun(id: string, index: string[]): string|nil  -- pure: the file the index names for a number, for a source whose files carry more than the number
---@field index fun(): cds.Task                    -- of the index text as one string
---@field entries fun(lines: string[]): rfc.Entry[]  -- pure
---@field render fun(id: string, lines: string[]): rfc.HelpDoc  -- pure, total
---@field placeholder nil|fun(lines: string[]): boolean  -- pure: whether a stored text stands in for the document rather than being it
---@field subjects nil|rfc.Subjects   -- the source's taxonomy, for a source that has one

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
        return fp.map(rfc.index(lines), function(e)
            local text = fp.any(e.formats, function(f)
                return f == "TXT"
            end)
            return { id = e.number, label = e.label, text = text }
        end)
    end,
    render = help.render,
    -- the RFC Editor's subject tags: a tree of 19 roots, four levels at
    -- most, published daily as a CSV by rfc-editor/rfc-subject-tags
    subjects = {
        index_file = "rfc-subjects.csv",
        index = function()
            return fetch.subjects()
        end,
        entries = subjects.rfc,
        title = "RFCs by subject",
        about = "From rfc-editor.github.io/rfc-subject-tags, the RFC Editor's subject tags (beta).",
    },
}

local EIPS = { repo = "ethereum/EIPs", dir = "EIPS", prefix = "eip" }
local ERCS = { repo = "ethereum/ERCs", dir = "ERCS", prefix = "erc" }
-- The site's category pages, which together list every proposal (the ERC
-- page lists the same numbers as the ERCs site's own) and name the
-- category each row belongs to, where the all page does not.
local EIP_SITE = "https://eips.ethereum.org/"
local EIP_CATEGORIES = { "core", "networking", "interface", "erc", "meta", "informational" }

--- The listing's entries with each number once; the first listing wins.
---@param lines string[]
---@return cds.eip.Entry[]
local function eip_entries(lines)
    return fp.unique(eip.listing(lines), function(e)
        return e.id
    end)
end

--- The six category pages, one after the other, as one text.
---@return cds.Task
local function eip_index()
    local pages = fp.map(EIP_CATEGORIES, function(c)
        return fetch.listing(EIP_SITE .. c, "the " .. c .. " EIP listing")
    end)
    return Task.all(pages):map(function(texts)
        return table.concat(texts, "\n")
    end)
end

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
    index_file = "eip-categories.html",
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
    index = eip_index,
    entries = function(lines)
        return fp.map(eip_entries(lines), function(e)
            return { id = e.id, label = e.title .. " (" .. e.status .. ")", text = true }
        end)
    end,
    render = help_eip.render,
    -- the categories, one level: the page a row came from
    subjects = {
        index_file = "eip-categories.html",
        index = eip_index,
        entries = function(lines)
            return fp.map(eip_entries(lines), function(e)
                return subjects.entry(e.id, e.title .. " (" .. e.status .. ")", { { e.category } })
            end)
        end,
        title = "EIPs by subject",
        about = "From eips.ethereum.org, the site's categories.",
    },
}

--- Every source, in the order the pickers list them.
--- Bitcoin's proposals, from bitcoin/bips on GitHub: most written in
--- MediaWiki, a few in markdown, the render telling them apart; the
--- repository's README is the index.
---@type rfc.Source
M.bip = {
    prefix = "bip",
    aliases = {},
    label = "BIP",
    raw_ext = "txt",
    index_file = "bip-index.mediawiki",
    fetch = function(id)
        return fetch.bip(id)
    end,
    index = function()
        return fetch.listing(fetch.github_raw .. "bitcoin/bips/master/README.mediawiki", "the BIP index")
    end,
    entries = function(lines)
        return fp.map(bip.index(lines), function(e)
            return { id = e.id, label = e.title .. " (" .. e.status .. ")", text = true }
        end)
    end,
    render = help_bip.render,
    -- the README's Layer and Type columns, each a root; a Process BIP has
    -- no layer and sits under Type alone
    subjects = {
        index_file = "bip-index.mediawiki",
        index = function()
            return fetch.listing(fetch.github_raw .. "bitcoin/bips/master/README.mediawiki", "the BIP index")
        end,
        entries = function(lines)
            return fp.map(bip.index(lines), function(e)
                local paths = fp.filter({ { "Layer", e.layer }, { "Type", e.type } }, function(facet)
                    return facet[2] ~= ""
                end)
                return subjects.entry(e.id, e.title .. " (" .. e.status .. ")", paths)
            end)
        end,
        title = "BIPs by subject",
        about = "From github.com/bitcoin/bips, the README's Layer and Type columns.",
    },
}

--- Solana's proposals, from solana-foundation/solana-improvement-documents
--- on GitHub. The proposals directory is the index, and a number finds its
--- file there, since the file name carries a slug too; the rim keeps the
--- directory a day, as it keeps every index.
---@type rfc.Source
M.simd = {
    prefix = "simd",
    aliases = {},
    label = "SIMD",
    raw_ext = "md",
    index_file = "simd-index.json",
    locate = function(id, index)
        local found = fp.find(simd.index(index), function(e)
            return e.id == id
        end)
        return found and found.file or nil
    end,
    fetch = function(id, file)
        return fetch.simd(file, id)
    end,
    index = function()
        return fetch.simd_listing()
    end,
    entries = function(lines)
        return fp.map(simd.index(lines), function(e)
            return { id = e.id, label = e.title, text = true }
        end)
    end,
    render = help_simd.render,
}

M.all = { M.rfc, M.eip, M.bip, M.simd }

--- The source a tag belongs to, by its prefix or one of the aliases, or
--- nil: a document's tag (eip1559-abstract) or a subjects tag
--- (eip-subjects, eip-subjects-core).
---@param tag string
---@return rfc.Source|nil
function M.of(tag)
    local prefix = tag:match("^(%l+)%d") or tag:match("^(%l+)%-subjects")
    if not prefix then
        return nil
    end
    return (
        fp.find(M.all, function(source)
            return source.prefix == prefix or vim.tbl_contains(source.aliases, prefix)
        end)
    )
end

return M

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
local help_w3c = require("rfc.help_w3c")
local rfc = require("cds.rfc")
local eip = require("cds.eip")
local bip = require("cds.bip")
local simd = require("cds.simd")
local w3c = require("cds.w3c")
local subjects = require("cds.subjects")
local Task = require("cds.task")
local fp = require("cds.fp")

local M = {}

---@class rfc.Entry
---@field id string
---@field label string      -- what the picker shows after the tag
---@field text boolean      -- whether the source has a text to render (an RFC published as PDF only has none)
---@field date string|nil   -- YYYY-MM-DD, when the index dates the document (a W3C report's publication)
---@field file string|nil   -- the document's file as the index spells it (a proposal's path, a report's URL), for a source that is `located`
---@field status string|nil -- where the document stands in its lifecycle (Draft, Final), for a source with `status`

---@class rfc.Subjects
---@field index_file string|nil   -- the cache file the subjects index is stored as; the source's own index file when the index carries the subjects
---@field index nil|fun(): cds.Task   -- of the index text as one string
---@field entries nil|fun(lines: string[]): cds.subjects.Entry[]|nil, string|nil  -- pure: the subjects from the index
---@field texts boolean|nil       -- the subjects come from the documents' own texts, every one the index names
---@field entry nil|fun(id: string, lines: string[]): cds.subjects.Entry  -- pure: a document's subjects from its text
---@field title string            -- the document's title: RFCs by subject
---@field about string            -- the line naming the data
---@field roots string[]|nil      -- the roots first, in this order; the rest follow by name

---@class rfc.Source
---@field prefix string     -- the tag prefix: rfc, eip
---@field key "number"|"shortname"|nil  -- what names a document: a number (rfc9110) unless said; a shortname joins with a dash (w3c-wcag22)
---@field aliases string[]  -- other prefixes whose tags this source answers: erc for eip
---@field label string      -- how a message names it: RFC, EIP
---@field raw_ext string    -- the extension the fetched text is stored under
---@field index_file string -- the cache file the index is stored as
---@field fetch fun(id: string, file?: string, since?: integer): cds.Task  -- of the text as one string; `file` is the entry's, for a located source; `since` the copy's time, for a source that asks conditionally
---@field located boolean|nil  -- the index names each document's file (its entries carry `file`), so a fetch goes through the index the rim keeps
---@field index fun(): cds.Task                    -- of the index text as one string
---@field entries fun(lines: string[]): rfc.Entry[]  -- pure
---@field render fun(id: string, lines: string[], file?: string): rfc.HelpDoc  -- pure, total; `file` is the entry's, for a located source
---@field placeholder nil|fun(lines: string[]): boolean  -- pure: whether a stored text stands in for the document rather than being it
---@field subjects nil|rfc.Subjects   -- the source's taxonomy, for a source that has one
---@field status nil|string[]    -- the lifecycle, in order, as the source's process lays it out; a status outside the list follows by name
---@field status_of nil|fun(lines: string[]): string|nil  -- pure: a document's status read from its text, for a source whose index carries none; known once the text is cached

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
            return { id = e.number, label = e.label, text = text, status = e.status }
        end)
    end,
    -- the standards track as RFC 2026 lays it out, then the other
    -- categories, as the index prints them
    status = {
        "PROPOSED STANDARD",
        "DRAFT STANDARD",
        "INTERNET STANDARD",
        "BEST CURRENT PRACTICE",
        "INFORMATIONAL",
        "EXPERIMENTAL",
        "HISTORIC",
        "UNKNOWN",
    },
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
    -- the EIPs repository first, then ERCs: a moved stub says the text is
    -- there, and an ERC filed since the repositories split has no stub at
    -- all, so a number EIPs refuses is asked of ERCs too, the first refusal
    -- being the one reported when both refuse
    fetch = function(id)
        local function from_ercs()
            return fetch.proposal(ERCS.repo, ERCS.dir, ERCS.prefix, id)
        end
        return fetch
            .proposal(EIPS.repo, EIPS.dir, EIPS.prefix, id)
            :recover(function(err)
                return from_ercs():map_err(function()
                    return err
                end)
            end)
            :bind(function(text)
                if moved(help.clean(text)) then
                    return from_ercs()
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
            return { id = e.id, label = e.title .. " (" .. e.status .. ")", text = true, status = e.status }
        end)
    end,
    render = help_eip.render,
    -- the lifecycle EIP-1 lays out, then the two ways out of it
    status = { "Draft", "Review", "Last Call", "Final", "Living", "Stagnant", "Withdrawn" },
    -- two roots: the category (the page a row came from), with the
    -- hardfork meta EIPs one level down since their titles file them so
    -- ("Hardfork Meta - Pectra"), and the status, so Last Call and Review
    -- read as lists
    subjects = {
        index_file = "eip-categories.html",
        index = eip_index,
        entries = function(lines)
            return fp.map(eip_entries(lines), function(e)
                local category = { e.category }
                if e.title:match("^Hardfork Meta") then
                    table.insert(category, "Hardforks")
                end
                return subjects.entry(e.id, e.title .. " (" .. e.status .. ")", { category, { "Status", e.status } })
            end)
        end,
        title = "EIPs by subject",
        about = "From eips.ethereum.org, the site's categories and statuses.",
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
            return { id = e.id, label = e.title .. " (" .. e.status .. ")", text = true, status = e.status }
        end)
    end,
    render = help_bip.render,
    -- the README's four statuses, in the order a BIP passes through them
    status = { "Draft", "Complete", "Deployed", "Closed" },
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
    located = true,
    fetch = function(id, file)
        return fetch.simd(file, id)
    end,
    index = function()
        return fetch.simd_listing()
    end,
    entries = function(lines)
        return fp.map(simd.index(lines), function(e)
            return { id = e.id, label = e.title, text = true, file = e.file }
        end)
    end,
    render = help_simd.render,
    -- the directory names no status; each proposal's frontmatter does, and
    -- SIMD-0001 lays the lifecycle out as idea to activation, living beside
    -- it, stagnant and withdrawn out of it
    status = { "Idea", "Draft", "Review", "Accepted", "Implemented", "Activated", "Living", "Stagnant", "Withdrawn" },
    status_of = function(lines)
        return eip.frontmatter(lines).status
    end,
    -- each proposal's status, from its frontmatter, so the subjects' inputs
    -- are the proposals' own texts; the category and the type are one
    -- value for near every proposal, so they say nothing
    subjects = {
        texts = true,
        entry = function(id, lines)
            local fields = eip.frontmatter(lines)
            local status = fields.status or ""
            local title = fields.title or ("SIMD " .. id)
            return subjects.entry(id, title .. " (" .. status .. ")", { { "Status", status } })
        end,
        title = "SIMDs by subject",
        about = "From the proposals' frontmatters, each one's status.",
    },
}

--- A report's picker label: its title, with the maturity when the index
--- gives one.
---@param e cds.w3c.Entry
---@return string
local function report_label(e)
    return e.maturity ~= "" and (e.title .. " (" .. e.maturity .. ")") or e.title
end

--- The W3C's technical reports, by shortname: the TR page is the index,
--- a report is fetched at the URL the page spells (89 shortnames carry
--- uppercase letters, and the lowercased URL only redirects), asked
--- conditionally when a copy is on disk, and rendered through cds.html.
---@type rfc.Source
M.w3c = {
    prefix = "w3c",
    aliases = {},
    label = "W3C",
    key = "shortname",
    raw_ext = "html",
    index_file = "w3c-index.html",
    located = true,
    fetch = function(id, url, since)
        return fetch.w3c(url, id, since)
    end,
    index = function()
        return fetch.listing("https://www.w3.org/TR/", "the W3C index")
    end,
    entries = function(lines)
        return fp.map(w3c.index(lines), function(e)
            return {
                id = e.id,
                label = report_label(e),
                text = true,
                date = e.date,
                file = e.url,
                status = e.maturity ~= "" and e.maturity or nil,
            }
        end)
    end,
    render = help_w3c.render,
    -- the maturities as the TR page names them: the Recommendation track,
    -- then the Note track, the Registry track and Statements
    status = {
        "Draft Standard",
        "Candidate Standard",
        "Standard",
        "Draft Note",
        "Note",
        "Draft Registry",
        "Candidate Registry",
        "Registry",
        "Statement",
    },
    -- three roots: the maturity, the tags, the groups by their short names
    -- (WG, IG), since 133 of 135 end in Working Group or Interest Group
    subjects = {
        index_file = "w3c-index.html",
        index = function()
            return fetch.listing("https://www.w3.org/TR/", "the W3C index")
        end,
        entries = function(lines)
            return fp.map(w3c.index(lines), function(e)
                local paths = e.maturity ~= "" and { { "Maturity", e.maturity } } or {}
                vim.list_extend(
                    paths,
                    fp.map(e.tags, function(tag)
                        return { "Tags", tag }
                    end)
                )
                vim.list_extend(
                    paths,
                    fp.map(e.groups, function(group)
                        return { "Deliverers", w3c.short_group(group) }
                    end)
                )
                return subjects.entry(e.id, report_label(e), paths)
            end)
        end,
        title = "W3C reports by subject",
        about = "From www.w3.org/TR, each report's maturity, tags and working group.",
        roots = { "Maturity", "Tags", "Deliverers" },
    },
}

M.all = { M.rfc, M.eip, M.bip, M.simd, M.w3c }

--- The source a tag belongs to, by its prefix or one of the aliases, or
--- nil: a document's tag (eip1559-abstract) or a subjects tag
--- (eip-subjects, eip-subjects-core).
---@param tag string
---@return rfc.Source|nil
function M.of(tag)
    -- the dashed form first, a prefix ending in a letter (w3c, rfc): the
    -- number form would read "w" from "w3c-…", and the dashed form must
    -- not read "rfc9110" from "rfc9110-3.1"
    local prefix = tag:match("^(%l[%l%d]-%l)%-") or tag:match("^(%l+)%d")
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

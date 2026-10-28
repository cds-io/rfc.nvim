local fetch = require("rfc.fetch")
local help = require("rfc.help")
local help_eip = require("rfc.help_eip")
local proposal = require("rfc.proposal")
local eip = require("rfc.source.eip")
local subjects = require("rfc.source.subjects")
local Task = require("cds.task")
local fp = require("cds.fp")

local M = {}

local EIPS = { repo = "ethereum/EIPs", dir = "EIPS", prefix = "eip" }
local ERCS = { repo = "ethereum/ERCs", dir = "ERCS", prefix = "erc" }
-- The site's category pages, which together list every proposal (the ERC
-- page lists the same numbers as the ERCs site's own) and name the
-- category each row belongs to, where the all page does not.
local EIP_SITE = "https://eips.ethereum.org/"
local EIP_CATEGORIES = { "core", "networking", "interface", "erc", "meta", "informational" }

--- The listing's entries with each number once; the first listing wins.
---@param lines string[]
---@return rfc.source.eip.Entry[]
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
    render_model = proposal.render_model,
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

M.eip.prepare = function(id, lines)
    return proposal.model(help_eip.spec, id, lines)
end
return M.eip

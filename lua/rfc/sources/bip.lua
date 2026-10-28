local fetch = require("rfc.fetch")
local proposal = require("rfc.proposal")
local help_bip = require("rfc.help_bip")
local bip = require("rfc.source.bip")
local subjects = require("rfc.source.subjects")
local fp = require("cds.fp")

local M = {}

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
    render_model = proposal.render_model,
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

M.bip.prepare = function(id, lines)
    return proposal.model(help_bip.spec, id, lines)
end
return M.bip

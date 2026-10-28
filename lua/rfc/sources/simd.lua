local fetch = require("rfc.fetch")
local proposal = require("rfc.proposal")
local help_simd = require("rfc.help_simd")
local eip = require("rfc.source.eip")
local simd = require("rfc.source.simd")
local subjects = require("rfc.source.subjects")
local fp = require("cds.fp")

local M = {}

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
    render_model = proposal.render_model,
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

M.simd.prepare = function(id, lines)
    return proposal.model(help_simd.spec, id, lines)
end
return M.simd

-- A Bitcoin proposal as a Vim help document: the declaration the proposal
-- render takes. The preamble becomes the header block; the body is read by
-- cds.bip, or by cds.eip for a proposal written in markdown, and the
-- preamble's own lines are left out of it. Nothing here touches the
-- editor.
local bip = require("cds.bip")
local eip = require("cds.eip")
local proposal = require("rfc.proposal")

local M = {}

---@type rfc.ProposalSpec
M.spec = {
    prefix = "bip",
    label = function()
        return "BIP"
    end,
    number = function(_, id)
        return "BIP-" .. id
    end,
    read = function(lines)
        local fields, first, last = bip.preamble(lines)
        if bip.format(lines) == "markdown" then
            return fields, eip.blocks(lines, last and last + 1 or 1)
        end
        return fields, bip.blocks(lines, first and { first = first, last = last } or nil)
    end,
    header = { "layer", "status", "type", "assigned" },
    rows = {
        { key = "requires", as = "links" },
        { key = "replaces", as = "links" },
        { key = "authors", as = "text" },
    },
    mentions = bip.mentions,
}

---@param id string
---@param lines string[]
---@return rfc.HelpDoc
function M.render(id, lines)
    return proposal.render(M.spec, id, lines)
end

return M

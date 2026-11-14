-- A Bitcoin proposal as a Vim help document: the declaration the proposal
-- render takes. The preamble becomes the header block; the body is read by
-- rfc.sources.bip.reader, or by rfc.sources.eip.reader for a proposal written in markdown, and the
-- preamble's own lines are left out of it. Nothing here touches the
-- editor.
local bip = require("rfc.sources.bip.reader")
local markdown = require("rfc.format.proposal.markdown")
local proposal = require("rfc.format.proposal")

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
            return fields, markdown.blocks(lines, last and last + 1 or 1)
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

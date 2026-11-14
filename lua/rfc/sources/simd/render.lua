-- A Solana improvement document as a Vim help document: the declaration
-- the proposal render takes. The frontmatter becomes the header block,
-- the number written as the document writes it (four digits), the authors
-- as one line; the body is read by rfc.format.proposal.markdown. Nothing here touches the
-- editor.
local markdown = require("rfc.format.proposal.markdown")
local simd = require("rfc.sources.simd.reader")
local proposal = require("rfc.format.proposal")

local M = {}

---@type rfc.ProposalSpec
M.spec = {
    prefix = "simd",
    label = function()
        return "SIMD"
    end,
    number = function(fields, id)
        return ("SIMD-%04d"):format(tonumber(simd.number(fields.simd) or id))
    end,
    read = function(lines)
        local fields, body = markdown.frontmatter(lines)
        return fields, markdown.blocks(lines, body)
    end,
    header = { "category", "type", "status", "created" },
    rows = {
        { key = "feature", as = "text" },
        { key = "supersedes", as = "links" },
        { key = "superseded-by", as = "links" },
        { key = "extends", as = "links" },
        { key = "authors", as = simd.list },
    },
    mentions = simd.mentions,
}

---@param id string
---@param lines string[]
---@return rfc.HelpDoc
function M.render(id, lines)
    return proposal.render(M.spec, id, lines)
end

return M

-- An Ethereum proposal as a Vim help document: the declaration the
-- proposal render takes. The frontmatter becomes the header block; a
-- proposal in the ERC category carries its ERC name as a second tag,
-- since the texts of other proposals use both, and one that moved says
-- where. Nothing here touches the editor.
local eip = require("rfc.source.eip")
local markdown = require("rfc.format.proposal.markdown")
local proposal = require("rfc.format.proposal")

local M = {}

---@param fields table<string, string>
---@return string
local function label(fields)
    return fields.category == "ERC" and "ERC" or "EIP"
end

---@type rfc.ProposalSpec
M.spec = {
    prefix = "eip",
    label = label,
    number = function(fields, id)
        return label(fields) .. "-" .. id
    end,
    read = function(lines)
        local fields, body = markdown.frontmatter(lines)
        return fields, markdown.blocks(lines, body)
    end,
    header = { "status", "type", "category", "created" },
    rows = {
        { key = "requires", as = "links" },
        { key = "author", as = "text" },
        function(fields, id)
            return fields.status == "Moved"
                    and { { text = "Moved: see " }, { text = "erc" .. id, target = "erc" .. id } }
                or nil
        end,
    },
    tags = function(fields, id)
        return fields.category == "ERC" and { "erc" .. id } or {}
    end,
    mentions = eip.mentions,
}

---@param id string
---@param lines string[]
---@return rfc.HelpDoc
function M.render(id, lines)
    return proposal.render(M.spec, id, lines)
end

return M

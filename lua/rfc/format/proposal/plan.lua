-- Shared proposal heading identities for both projections.
local help = require("rfc.help.tags")
local document = require("cds.document")
local M = {}

---@class rfc.ProposalBlock
---@field kind "heading"|"fence"|"table"|"notes"|"line"
---@field level integer|nil
---@field title string|nil
---@field lang string|nil
---@field code string[]|nil
---@field caption string|nil
---@field header boolean|nil
---@field rows string[][]|nil
---@field notes { n: integer, text: string }[]|nil
---@field text string|nil

--- Heading identity is planned once for both renderers.
---@param blocks rfc.ProposalBlock[]
---@param file_tag string
---@return rfc.ProposalPlan
function M.plan_body(blocks, file_tag)
    local tag_of, texts, top, headings, bases = {}, {}, nil, {}, {}
    for _, b in ipairs(blocks) do
        if b.kind == "heading" then
            local level = assert(b.level, "a heading carries its level")
            top = math.min(top or level, level)
            headings[#headings + 1], bases[#bases + 1] = b, file_tag .. "-" .. help.slug(b.title)
            texts[b] = b.level <= 2 and b.title:upper() or b.title
        end
    end
    for i, name in ipairs(document.unique_names(bases, 2)) do
        tag_of[headings[i]] = name
    end
    return { tags = tag_of, texts = texts, top = top or 1 }
end

return M

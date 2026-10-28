-- Help projection of a prepared proposal.
local help = require("rfc.help")
local inline = require("rfc.proposal.inline")
local help_link = inline.help_link
local projection = require("rfc.proposal.body")
local M = {}

---@param model rfc.ProposalModel
---@return rfc.HelpDoc
function M.render_model(model)
    local blocks, file_tag = model.blocks, model.name
    local out, tags = {}, {}
    local function put(line)
        table.insert(out, line)
    end
    local function tag(name)
        table.insert(tags, { name = name, line = #out })
    end

    put(help.with_tag("*" .. file_tag .. ".txt*  " .. model.title, file_tag))
    tag(file_tag)
    tag(file_tag .. ".txt")
    for _, name in ipairs(model.aliases) do
        out[1] = out[1] .. " *" .. name .. "*"
        tag(name)
    end
    for _, line in ipairs(model.header) do
        put(inline.format(line, help_link))
    end
    put("")

    local body, body_tags = projection.body(blocks, file_tag, function(text)
        return inline.format(model.inlines[text], help_link)
    end, model.body)
    local offset = #out
    for _, line in ipairs(body) do
        put(line)
    end
    for _, t in ipairs(body_tags) do
        table.insert(tags, { name = t.name, line = offset + t.line })
    end
    put("")
    put(help.MODELINE)
    put(help.FOOTER)
    return { lines = out, tags = tags, model = model }
end

return M

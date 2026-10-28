---@class rfc.ReportModel
---@field kind "html"
---@field name string
---@field id string
---@field lines string[]
---@field url string
---@field head table
---@field blocks rfc.source.html.Block[]
---@field tag_of table<rfc.source.html.Block, string>
---@field sections table<string, string>
---@field refs table<string, string>
---@field ref_tag table<string, string>

-- A W3C technical report as a Vim help document: the head (title,
-- subtitle, metadata), a contents block of links, then the body's blocks
-- folded into help form: numbered headings with tags, prose wrapped at 78,
-- code fenced, tables aligned under their captions, lists and definition
-- lists indented, figures as caption, alt and URL, callouts as a labelled
-- block. Sections, other reports and reference entries link. Nothing here
-- touches the editor; render is pure and total.
local text = require("rfc.help.w3c.text")
local plan = require("rfc.help.w3c.model")
local render_blocks = require("rfc.help.w3c.blocks").render
local help = require("rfc.help")
local link = text.link
local M = { wrap = text.wrap, heading_tags = plan.heading_tags, model = plan.model }

---@param id string
---@param lines string[]
---@param url string
---@return rfc.HelpDoc
function M.render(id, lines, url)
    return M.render_model(M.model(id, lines, url))
end

---@param model rfc.ReportModel
---@return rfc.HelpDoc
function M.render_model(model)
    local id, url = model.id, model.url
    local head, blocks, file_tag = model.head, model.blocks, model.name
    local tag_of, sections, refs, ref_tag = model.tag_of, model.sections, model.refs, model.ref_tag
    local out = {}
    local tags = { { name = file_tag, line = 1 }, { name = file_tag .. ".txt", line = 1 } }
    local ctx =
        { out = out, tags = tags, tag_of = tag_of, sections = sections, refs = refs, ref_tag = ref_tag, url = url }

    table.insert(out, help.with_tag("*" .. file_tag .. ".txt*  " .. (head.title ~= "" and head.title or id), file_tag))
    if head.subtitle ~= "" then
        table.insert(out, head.subtitle)
    end
    for _, m in ipairs(head.meta) do
        local term = m.term:match(":$") and m.term or (m.term .. ":")
        for _, l in ipairs(M.wrap(term .. " " .. link(m.text, ctx), "")) do
            table.insert(out, l)
        end
    end
    table.insert(out, "")
    for _, b in ipairs(blocks) do
        if b.kind == "heading" then
            local row = ("%s|%s|  %s%s"):format(
                string.rep("  ", b.level - 1),
                tag_of[b],
                b.number and (b.number .. " ") or "",
                b.text.text
            )
            table.insert(out, row)
        end
    end
    table.insert(out, "")
    render_blocks(blocks, "", ctx)
    if out[#out] ~= "" then
        table.insert(out, "")
    end
    table.insert(out, help.MODELINE)
    table.insert(out, help.FOOTER)
    return { lines = out, tags = tags, model = model }
end

return M

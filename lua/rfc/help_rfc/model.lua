-- RFC source plan and mention resolution.
local rfc = require("rfc.source.rfc")
local tags = require("rfc.help.tags")
local text = require("rfc.help.text")
local M = {}

--- The context a body line is rewritten in.
---@class rfc.help.Context
---@field rfc_num string
---@field known table<string, boolean>   -- section tags this document defines
---@field ref_tags table<string, string> -- citation (with brackets) -> its ref tag
---@field cite_rfc fun(citation: string): string|nil

--- The tag a mention links to, or nil when it has none: a same-document
--- section links only when its heading was found, since a link to nothing
--- is a dead end; a citation only when the references list it, and never
--- the one a reference entry is defining on that line.
---@param m rfc.source.rfc.Mention
---@param ctx rfc.help.Context
---@param own? string   -- the citation the line defines, if it is a reference entry
---@return string|nil
function M.target(m, ctx, own)
    if m.kind == "rfc" then
        return "rfc" .. m.rfc
    elseif m.kind == "citation" then
        return m.citation ~= own and ctx.ref_tags[m.citation] or nil
    end
    local target = m.rfc or (m.citation and ctx.cite_rfc(m.citation))
    if target then
        return "rfc" .. target .. "-" .. m.number
    end
    local here = "rfc" .. ctx.rfc_num .. "-" .. m.number
    return ctx.known[here] and here or nil
end
--- The document for an RFC's text: one fold over the reader's blocks.
--- Every block links what it names, then gets its kind's decoration: the
--- tag on a heading or a reference entry, the row link on a ToC row; a
--- page header is left as written.
---@param rfc_num string
---@param lines string[]
---@return rfc.RfcModel
function M.model(rfc_num, lines)
    local blocks = rfc.blocks(lines)
    local file_tag = "rfc" .. rfc_num
    local tag_of, known, ref_tags, entry_at = {}, {}, {}, {}
    for _, b in ipairs(blocks) do
        if b.kind == "heading" or b.kind == "row" then
            local tag = tags.tag(rfc_num, b.section.number, b.section.title)
            tag_of[b] = tag
            known[tag] = true
        elseif b.kind == "reference" then
            entry_at[b.citation] = b.line
            if not b.citation:match("^%[RFC%d+%]$") then
                tag_of[b] = tags.ref_tag(rfc_num, b.citation)
                ref_tags[b.citation] = tag_of[b]
            end
        end
    end
    local ctx = {
        rfc_num = rfc_num,
        known = known,
        ref_tags = ref_tags,
        cite_rfc = function(citation)
            return entry_at[citation] and rfc.cited_rfc(lines, entry_at[citation])
        end,
    }

    return {
        kind = "rfc",
        name = file_tag,
        title = text.title(lines) or ("RFC " .. rfc_num),
        blocks = blocks,
        tag_of = tag_of,
        context = ctx,
    }
end

return M

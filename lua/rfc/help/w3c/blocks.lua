-- Recursive report help projection.
local help = require("rfc.help")
local proposal = require("rfc.proposal")
local fp = require("cds.fp")
local formatting = require("rfc.help.w3c.text")
local link, absolute = formatting.link, formatting.absolute
local WIDTH = 78
local M = {}

--- The blocks rendered under an indent, appended to `out`, with the tags
--- they declare appended to `tags`.
---@param blocks rfc.source.html.Block[]
---@param indent string
---@param ctx table
local function render_blocks(blocks, indent, ctx)
    local out, tags = ctx.out, ctx.tags
    local function put(line)
        table.insert(out, line)
    end
    local function blank()
        if out[#out] ~= "" then
            put("")
        end
    end
    local function paragraph(t, ind)
        for _, l in ipairs(formatting.wrap(link(t, ctx), ind)) do
            put(l)
        end
    end
    for _, b in ipairs(blocks) do
        if b.kind == "heading" then
            blank()
            local text = (b.number and (b.number .. " ") or "") .. link(b.text, ctx)
            if b.level <= 2 then
                text = text:upper()
            end
            put(help.with_tag(text, ctx.tag_of[b]))
            table.insert(tags, { name = ctx.tag_of[b], line = #out })
        elseif b.kind == "para" then
            paragraph(b.text, indent)
            blank()
        elseif b.kind == "quote" then
            render_blocks(b.blocks, indent .. "    ", ctx)
            blank()
        elseif b.kind == "code" then
            -- the fences sit at the margin whatever the indent: help reads
            -- them there and nowhere else
            put(">" .. b.lang)
            for _, l in ipairs(b.code) do
                put(l == "" and "" or (indent .. "    " .. l))
            end
            put("<")
            blank()
        elseif b.kind == "table" then
            put(indent .. (b.caption or "Table") .. " ~")
            local rows = fp.map(b.rows, function(r)
                return fp.map(r, function(c)
                    return link(c, ctx)
                end)
            end)
            for _, l in ipairs(proposal.layout({ caption = nil, header = b.header, rows = rows })) do
                put(indent .. l)
            end
            blank()
        elseif b.kind == "list" then
            for i, item in ipairs(b.items) do
                local marker = b.ordered and (i .. ". ") or "- "
                local inner = indent .. string.rep(" ", #marker)
                local first = item[1]
                if first and first.kind == "para" then
                    local wrapped = formatting.wrap(link(first.text, ctx), inner)
                    wrapped[1] = indent .. marker .. wrapped[1]:sub(#inner + 1)
                    for _, l in ipairs(wrapped) do
                        put(l)
                    end
                    render_blocks({ unpack(item, 2) }, inner, ctx)
                else
                    put(indent .. marker)
                    render_blocks(item, inner, ctx)
                end
            end
            blank()
        elseif b.kind == "dl" then
            for _, e in ipairs(b.entries) do
                local tag = ctx.ref_tag[e.term]
                if tag then
                    put(help.with_tag(indent .. e.term, tag))
                    table.insert(tags, { name = tag, line = #out })
                else
                    put(indent .. e.term)
                end
                render_blocks(e.blocks, indent .. "    ", ctx)
            end
            blank()
        elseif b.kind == "figure" then
            put(indent .. (b.caption or "Figure") .. " ~")
            if b.alt ~= "" then
                for _, l in ipairs(formatting.wrap(b.alt, indent .. "    ")) do
                    put(l)
                end
            end
            if b.src ~= "" then
                put(indent .. "    " .. absolute(b.src, ctx.url))
            end
            blank()
        elseif b.kind == "callout" then
            -- a label may be a sentence (a details summary): wrapped, each
            -- line a column heading
            for _, l in ipairs(formatting.wrap(b.label, indent, WIDTH - 2)) do
                put(l .. " ~")
            end
            render_blocks(b.blocks, indent .. "  ", ctx)
            blank()
        elseif b.kind == "rule" then
            blank()
        end
    end
end

M.render = render_blocks

return M

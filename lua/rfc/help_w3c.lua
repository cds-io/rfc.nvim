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
local html = require("rfc.source.html")
local help = require("rfc.help")
local proposal = require("rfc.proposal")
local fp = require("cds.fp")

local M = {}

local WIDTH = 78

--- The text wrapped at spaces within the width, each line under the
--- indent; a word longer than the room (a |tag|) stands alone on a line;
--- a newline in the text is a hard break.
---@param text string
---@param indent string
---@param width? integer
---@return string[]
function M.wrap(text, indent, width)
    width = width or WIDTH
    local out = {}
    for piece in (text .. "\n"):gmatch("(.-)\n") do
        local line = nil
        for word in piece:gmatch("%S+") do
            if not line then
                line = indent .. word
            elseif #line + 1 + #word <= width then
                line = line .. " " .. word
            else
                table.insert(out, line)
                line = indent .. word
            end
        end
        table.insert(out, line or indent:gsub("%s+$", ""))
    end
    return out
end

--- The image URL made absolute against the report's.
---@param src string
---@param url string   -- the report's URL, with or without its trailing slash
---@return string
local function absolute(src, url)
    if src:match("^https?://") then
        return src
    elseif src:match("^/") then
        return "https://www.w3.org" .. src
    end
    return (url:match("/$") and url or url .. "/") .. src
end

--- The text with its mentions as links, last to first so the earlier
--- spans stay where they were.
---@param t rfc.source.html.Text
---@param ctx table
---@return string
local function link(t, ctx)
    local s = t.text
    for i = #t.mentions, 1, -1 do
        local m = t.mentions[i]
        local tag
        if m.kind == "section" then
            tag = ctx.sections[m.section]
        elseif m.kind == "report" then
            tag = "w3c-" .. m.id:lower()
        elseif m.kind == "reference" then
            tag = ctx.refs[m.id:lower()]
        end
        if tag then
            s = s:sub(1, m.first - 1) .. "|" .. tag .. "|" .. s:sub(m.last + 1)
        end
    end
    return s
end

--- The heading tags, by block, numbered on a repeat, and the ids each
--- heading answers for a section link: its own and its section's (ReSpec
--- gives both, and links target the section's). A number that is words
--- (WCAG's "Success Criterion 1.1.1") is slugged, since a tag has no
--- spaces.
---@param blocks rfc.source.html.Block[]
---@param file_tag string
---@return table<table, string> tag_of
---@return table<string, string> sections   -- id -> tag
function M.heading_tags(blocks, file_tag)
    local tag_of, sections, used = {}, {}, {}
    for _, b in ipairs(blocks) do
        if b.kind == "heading" then
            local name = b.number and (b.number:match("^[%w%.]+$") or help.slug(b.number)) or help.slug(b.text.text)
            local tag = file_tag .. "#" .. name
            if used[tag] then
                used[tag] = used[tag] + 1
                tag = tag .. "-" .. used[tag]
            else
                used[tag] = 1
            end
            tag_of[b] = tag
            if b.id then
                sections[b.id] = tag
            end
            if b.section then
                -- the section's first heading is its own
                sections[b.section] = sections[b.section] or tag
            end
        end
    end
    return tag_of, sections
end

--- The reference entries: every term of a definition list under a
--- "References" heading, keyed lowercase without its brackets.
---@param blocks rfc.source.html.Block[]
---@param file_tag string
---@return table<string, string> refs       -- key -> tag
---@return table<string, string> ref_tag    -- term as written -> tag
local function reference_tags(blocks, file_tag)
    local refs, ref_tag, in_refs, depth = {}, {}, false, nil
    for _, b in ipairs(blocks) do
        if b.kind == "heading" then
            if b.text.text:lower():match("references") then
                in_refs, depth = true, depth or b.level
            elseif depth and b.level <= depth then
                in_refs = false
            end
        elseif b.kind == "dl" and in_refs then
            for _, e in ipairs(b.entries) do
                local key = e.term:gsub("^%[", ""):gsub("%]$", "")
                local tag = file_tag .. "#ref-" .. key:gsub("[^%w%.%-]+", "-")
                refs[key:lower()] = tag
                ref_tag[e.term] = tag
            end
        end
    end
    return refs, ref_tag
end

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
        for _, l in ipairs(M.wrap(link(t, ctx), ind)) do
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
                    local wrapped = M.wrap(link(first.text, ctx), inner)
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
                for _, l in ipairs(M.wrap(b.alt, indent .. "    ")) do
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
            for _, l in ipairs(M.wrap(b.label, indent, WIDTH - 2)) do
                put(l .. " ~")
            end
            render_blocks(b.blocks, indent .. "  ", ctx)
            blank()
        elseif b.kind == "rule" then
            blank()
        end
    end
end

--- The document for a report: the head, the contents, the body.
---@param id string       -- the lowercased shortname
---@param lines string[]  -- the report's HTML
---@param url string      -- the report's URL, for the figures
---@return rfc.ReportModel
function M.model(id, lines, url)
    local head = html.head(lines)
    local blocks = html.blocks(lines)
    local file_tag = "w3c-" .. id
    local tag_of, sections = M.heading_tags(blocks, file_tag)
    local refs, ref_tag = reference_tags(blocks, file_tag)
    return {
        kind = "html",
        name = file_tag,
        id = id,
        lines = lines,
        url = url,
        head = head,
        blocks = blocks,
        tag_of = tag_of,
        sections = sections,
        refs = refs,
        ref_tag = ref_tag,
    }
end

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

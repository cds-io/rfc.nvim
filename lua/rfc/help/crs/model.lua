-- A CRS report's document model: the same `html` report model a W3C report
-- gets, so rfc.help_w3c renders it as help and rfc.document.report as the
-- Markdown document, built from the stored text the fetch wrote (the fact
-- line, then the mirror's HTML). The lines are normalized here, on every
-- render, so the raw file stays the site's HTML and a render upgrade meets
-- a better normalization. The head reads the title and the "Updated" line
-- from the report's header, and the version count, the first date, the
-- topics and the links back to the original from the fact line; without a
-- fact line the head says what the header alone says. Pure and total.
local crs = require("rfc.source.crs")
local html = require("rfc.source.html")
local plan = require("rfc.help.w3c.model")
local converter = require("cds.html")

---@class rfc.help.crs.model
local M = {}

--- A head metadata entry, as the W3C head carries them.
---@param term string
---@param text string
---@return { term: string, text: rfc.source.html.Text }
local function meta(term, text)
    return { term = term, text = { text = text, mentions = {} } }
end

--- The subtitle: the product and number, the header's updated line, and
--- what the fact line says of the versions.
---@param number string
---@param head rfc.source.crs.Head
---@param facts table|nil
---@return string
local function subtitle(number, head, facts)
    local parts = { "CRS " .. crs.kind(number) .. " " .. number }
    if head.updated ~= "" then
        table.insert(parts, head.updated)
    end
    if facts and facts.versions > 1 then
        table.insert(parts, ("%d versions since %s"):format(facts.versions, crs.long_date(facts.first)))
    elseif facts and facts.versions == 1 then
        table.insert(parts, "1 version")
    end
    return table.concat(parts, " · ")
end

--- The metadata lines: the topics, then each link the fact line carries.
---@param facts table|nil
---@return { term: string, text: rfc.source.html.Text }[]
local function metadata(facts)
    local out = {}
    if not facts then
        return out
    end
    if #facts.topics > 0 then
        table.insert(out, meta("Topics", table.concat(facts.topics, ", ")))
    end
    if facts.pdf then
        table.insert(out, meta("PDF", facts.pdf))
    end
    if facts.mirror then
        table.insert(out, meta("Mirror PDF", crs.BASE .. facts.mirror))
    end
    if facts.source then
        table.insert(out, meta("Source", facts.source))
    end
    return out
end

--- The text's few HTML-significant characters escaped.
---@param s string
---@return string
local function escape(s)
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

--- The head as HTML, for the Markdown view, which renders the lines and
--- not the head: the title, the subtitle, and each metadata line with its
--- URL a link. The help view builds its own head from `model.head`, so
--- these lines stay out of the blocks.
---@param title string
---@param sub string
---@param entries { term: string, text: rfc.source.html.Text }[]
---@return string[]
local function head_html(title, sub, entries)
    local out = { '<div class="crs-head">', "<h1>" .. escape(title) .. "</h1>", "<p>" .. escape(sub) .. "</p>" }
    for _, m in ipairs(entries) do
        local value = m.text.text
        if value:match("^https?://") then
            value = '<a href="' .. value .. '">' .. value .. "</a>"
        else
            value = escape(value)
        end
        table.insert(out, "<p>" .. escape(m.term) .. ": " .. value .. "</p>")
    end
    table.insert(out, "</div>")
    return out
end

--- The note over a report the mirror rendered from its PDF with a text
--- extractor (cds.html.flattened over the stored HTML): a labelled note
--- both readers draw, the shared wording, and the publisher's PDF, else the
--- mirror's, as the copy with the layout.
---@param facts table|nil
---@return string[]
local function dump_note(facts)
    local pdf = facts and (facts.pdf or (facts.mirror and crs.BASE .. facts.mirror)) or nil
    local out = converter.FLATTENED_NOTICE
    if pdf then
        out = out .. ' Visit the PDF for the proper formatting: <a href="' .. pdf .. '">' .. pdf .. "</a>"
    end
    return {
        '<div class="note"><p class="note-title">Upstream conversion error</p>',
        "<p>" .. out .. "</p>",
        "</div>",
    }
end

--- The model for a report. `url` is what the cache passes a source that is
--- not located, nil; the report's page on the mirror stands in, since the
--- Markdown render resolves relative links against it. A body that is a
--- text dump opens with dump_note, ahead of its blocks in both views.
---@param id string         -- the lowercased number: r43397
---@param lines string[]    -- the stored text
---@return rfc.ReportModel
function M.model(id, lines)
    local facts = crs.read_facts(lines[1] or "")
    local body = facts and { unpack(lines, 2) } or lines
    local normalized, head = crs.normalize(body)
    if converter.flattened(table.concat(body, "\n")) then
        local noted = dump_note(facts)
        for _, l in ipairs(normalized) do
            table.insert(noted, l)
        end
        normalized = noted
    end
    local number = (facts and facts.id ~= "" and facts.id) or (head.number ~= "" and head.number) or id:upper()
    local file_tag = "crs-" .. id
    local blocks = html.blocks(normalized)
    local tag_of, sections = plan.heading_tags(blocks, file_tag)
    local title, sub = head.title ~= "" and head.title or number, subtitle(number, head, facts)
    local entries = metadata(facts)
    local lines_out = head_html(title, sub, entries)
    for _, l in ipairs(normalized) do
        table.insert(lines_out, l)
    end
    return {
        kind = "html",
        name = file_tag,
        id = id,
        lines = lines_out,
        url = crs.BASE .. "reports/" .. number .. ".html",
        head = { title = title, subtitle = sub, meta = entries, abstract = {} },
        blocks = blocks,
        tag_of = tag_of,
        sections = sections,
        refs = {},
        ref_tag = {},
    }
end

return M

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

--- The model for a report. `url` is what the cache passes a source that is
--- not located, nil; the report's page on the mirror stands in, since the
--- Markdown render resolves relative links against it.
---@param id string         -- the lowercased number: r43397
---@param lines string[]    -- the stored text
---@return rfc.ReportModel
function M.model(id, lines)
    local facts = crs.read_facts(lines[1] or "")
    local body = facts and { unpack(lines, 2) } or lines
    local normalized, head = crs.normalize(body)
    local number = (facts and facts.id ~= "" and facts.id) or (head.number ~= "" and head.number) or id:upper()
    local file_tag = "crs-" .. id
    local blocks = html.blocks(normalized)
    local tag_of, sections = plan.heading_tags(blocks, file_tag)
    return {
        kind = "html",
        name = file_tag,
        id = id,
        lines = normalized,
        url = crs.BASE .. "reports/" .. number .. ".html",
        head = {
            title = head.title ~= "" and head.title or number,
            subtitle = subtitle(number, head, facts),
            meta = metadata(facts),
            abstract = {},
        },
        blocks = blocks,
        tag_of = tag_of,
        sections = sections,
        refs = {},
        ref_tag = {},
    }
end

return M

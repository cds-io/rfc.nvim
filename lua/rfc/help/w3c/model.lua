-- Report headings, references and shared source plan.
local html = require("rfc.source.html")
local help = require("rfc.help.tags")
local document = require("cds.document")
local M = {}

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
    local tag_of, sections, headings, bases = {}, {}, {}, {}
    for _, b in ipairs(blocks) do
        if b.kind == "heading" then
            local name = b.number and (b.number:match("^[%w%.]+$") or help.slug(b.number)) or help.slug(b.text.text)
            headings[#headings + 1], bases[#bases + 1] = b, file_tag .. "#" .. name
        end
    end
    for i, tag in ipairs(document.unique_names(bases, 2)) do
        local b = headings[i]
        tag_of[b] = tag
        if b.id then
            sections[b.id] = tag
        end
        if b.section then
            sections[b.section] = sections[b.section] or tag
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

return M

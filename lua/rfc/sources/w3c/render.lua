-- A W3C technical report as a Vim help document: the report format over a
-- model whose tags are w3c-<shortname>. Nothing here touches the editor;
-- render is pure and total.
local html = require("rfc.source.html")
local report = require("rfc.format.report")
local M = { render_model = report.render_model }

--- The document for a report: the head, the contents, the body.
---@param id string       -- the lowercased shortname
---@param lines string[]  -- the report's HTML
---@param url string      -- the report's URL, for the figures
---@return rfc.ReportModel
function M.model(id, lines, url)
    local head = html.head(lines)
    local blocks = html.blocks(lines)
    local file_tag = "w3c-" .. id
    local tag_of, sections = report.heading_tags(blocks, file_tag)
    local refs, ref_tag = report.reference_tags(blocks, file_tag)
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

return M

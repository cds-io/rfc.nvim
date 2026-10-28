-- Retain HTML IDs and application tags in shared report documents.
local html = require("cds.html")
--- Use the original HTML IDs and the help renderer's tag names for reports.
---@param model rfc.ReportModel
---@return rfc.Document
local function report(model)
    local name, lines, url, blocks, names = model.name, model.lines, model.url, model.blocks, model.tag_of
    if not url:match("/$") then
        url = url .. "/"
    end
    local doc = html.document(table.concat(lines, "\n"), {
        base = url,
        page = true,
        region = "body",
        drop = { head = true, script = true, style = true, nav = true, footer = true },
    }) --[[@as rfc.Document]]
    doc.anchors[name], doc.anchors[name .. ".txt"] = 1, 1
    doc.headings = {}
    for _, block in ipairs(blocks) do
        if block.kind == "heading" then
            local row = block.id and doc.anchors[block.id] or block.section and doc.anchors[block.section]
            if row then
                local tag = names[block]
                doc.anchors[tag] = row
                table.insert(doc.headings, {
                    tag = tag,
                    text = (block.number and block.number .. " " or "") .. block.text.text,
                    level = block.level,
                    line = row,
                })
            end
        end
    end
    -- Reference tags have stable bibliography IDs in ReSpec/Bikeshed HTML.
    local references = {}
    for anchor, row in pairs(doc.anchors) do
        local key = anchor:match("^biblio%-(.+)$")
        if key then
            references[name .. "#ref-" .. key] = row
            references[name .. "#ref-" .. key:upper()] = row
        end
    end
    for tag, row in pairs(references) do
        doc.anchors[tag] = row
    end
    return doc
end

return report

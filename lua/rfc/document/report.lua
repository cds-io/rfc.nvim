-- Retain HTML IDs and application tags in shared report documents.
local html = require("cds.html")
--- Use the original HTML IDs and the help renderer's tag names for reports.
---@param model rfc.ReportModel
---@return rfc.Document
local function report(model)
    local id, lines, url, blocks, names = model.id, model.lines, model.url, model.blocks, model.tag_of
    if not url:match("/$") then
        url = url .. "/"
    end
    local doc = html.document(table.concat(lines, "\n"), {
        base = url,
        page = true,
        region = "body",
        drop = { head = true, script = true, style = true, nav = true, footer = true },
    }) --[[@as rfc.Document]]
    doc.anchors["w3c-" .. id], doc.anchors["w3c-" .. id .. ".txt"] = 1, 1
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
    for name, row in pairs(doc.anchors) do
        local key = name:match("^biblio%-(.+)$")
        if key then
            references["w3c-" .. id .. "#ref-" .. key] = row
            references["w3c-" .. id .. "#ref-" .. key:upper()] = row
        end
    end
    for name, row in pairs(references) do
        doc.anchors[name] = row
    end
    return doc
end

return report

-- Source-specific tags over the shared Markdown/anchor/link contract. Help
-- exports remain canonical for tag naming; W3C bodies use the shared HTML reader.
local document = require("cds.document")
local html = require("cds.html")
local help = require("rfc.help")
local outline = require("rfc.outline")

local M = {}

---@class rfc.Document: cds.Document
---@field headings rfc.Heading[]

--- A help export as Markdown, with every declared tag retained as an anchor.
---@param lines string[]
---@return rfc.Document
function M.from_help(lines)
    local headings, at, mapping, out = outline.of(lines), {}, {}, {}
    for _, h in ipairs(headings) do
        at[h.line] = h
    end
    local code = false
    for row, line in ipairs(lines) do
        if not line:match("^ vim:") and not line:match("^ rfc%.nvim render ") then
            local opening = not code and line:match("^>([%w_+-]*)$")
            if opening then
                code = true
                line = "```" .. opening
            elseif code and line == "<" then
                code = false
                line = "```"
            elseif not code then
                if row == 1 then
                    line = "# " .. html.escape((line:gsub("%*[^*]+%*", ""):match("^%s*(.-)%s*$")))
                elseif at[row] then
                    line = string.rep("#", math.min(at[row].level + 1, 6)) .. " " .. at[row].text
                else
                    line = line:gsub("%s*%*[^*%s]+%*", "")
                end
                line = line:gsub("|([^|%s]+)|", function(tag)
                    return "[" .. tag .. "](rfc-tag:" .. tag .. ")"
                end)
            end
            out[#out + 1] = line
            mapping[row] = #out
        end
    end
    local anchors = {}
    for _, tag in ipairs(help.tags_in(lines)) do
        anchors[tag.name] = mapping[tag.line]
    end
    local doc = document.new(out, { anchors = anchors }) --[[@as rfc.Document]]
    doc.headings = {}
    for _, h in ipairs(headings) do
        table.insert(doc.headings, { tag = h.tag, text = h.text, level = h.level, line = mapping[h.line] })
    end
    return doc
end

--- Use the original HTML IDs and the help renderer's tag names for reports.
---@param id string
---@param lines string[]
---@param url string
---@return rfc.Document
function M.report(id, lines, url)
    if not url:match("/$") then
        url = url .. "/"
    end
    local source_html = require("rfc.source.html")
    local blocks = source_html.blocks(lines)
    local names = require("rfc.help_w3c").heading_tags(blocks, "w3c-" .. id)
    local doc = html.document(table.concat(lines, "\n"), { base = url, page = true }) --[[@as rfc.Document]]
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

return M

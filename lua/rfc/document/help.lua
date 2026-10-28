-- Source-specific tags over the shared Markdown/anchor/link contract. Help
-- exports and Markdown use common source plans; W3C bodies use the shared HTML reader.
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
    local tags, declarations = help.tags_in(lines), {}
    for _, tag in ipairs(tags) do
        declarations[tag.line] = declarations[tag.line] or {}
        declarations[tag.line][tag.name] = true
    end
    local function strip_tags(line, row)
        return (
            line:gsub("(%s*)%*([^*%s]+)%*", function(space, name)
                return declarations[row] and declarations[row][name] and "" or space .. "*" .. name .. "*"
            end)
        )
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
                    line = "# " .. html.escape((strip_tags(line, row):match("^%s*(.-)%s*$")))
                elseif at[row] then
                    line = string.rep("#", math.min(at[row].level + 1, 6)) .. " " .. html.escape(at[row].text)
                else
                    line = strip_tags(line, row):gsub("%*", "\\*")
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
    for _, tag in ipairs(tags) do
        anchors[tag.name] = mapping[tag.line]
    end
    local doc = document.new(out, { anchors = anchors }) --[[@as rfc.Document]]
    doc.headings = {}
    for _, h in ipairs(headings) do
        table.insert(doc.headings, { tag = h.tag, text = h.text, level = h.level, line = mapping[h.line] })
    end
    return doc
end

return M.from_help

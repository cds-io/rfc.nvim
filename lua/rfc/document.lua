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

--- Render the Markdown view directly from the same source plan as help.
--- No formatted help text is scanned to recover prose, code, tags or links.
---@param model rfc.SourceModel
---@return rfc.Document
function M.from_model(model)
    if model.kind == "html" then
        return report(model)
    end
    local out, anchors, headings = { "# " .. html.escape(model.title) }, {}, {}
    anchors[model.name], anchors[model.name .. ".txt"] = 1, 1
    if model.kind == "proposal" then
        for _, alias in ipairs(model.aliases) do
            anchors[alias] = 1
        end
    end
    local function put(text)
        table.insert(out, text)
    end
    local function prose(text)
        local code = {}
        text = text:gsub("`[^`]*`", function(span)
            code[#code + 1] = span
            return "\3" .. #code .. "\4"
        end):gsub("%*", "\\*")
        return (text:gsub("\3(%d+)\4", function(index)
            return code[tonumber(index)]
        end))
    end
    local function linked(text, mentions, resolve)
        for i = #mentions, 1, -1 do
            local m = mentions[i]
            local target = resolve(m)
            if target then
                text = text:sub(1, m.first - 1) .. "\1" .. i .. "\2" .. text:sub(m.last + 1)
            end
        end
        text = prose(text)
        return (
            text:gsub("\1(%d+)\2", function(index)
                local target = resolve(mentions[tonumber(index)])
                return "[" .. target .. "](rfc-tag:" .. target .. ")"
            end)
        )
    end
    local function heading(tag, text, level, markdown)
        put(string.rep("#", math.min(level + 1, 6)) .. " " .. (markdown or html.escape(text)))
        anchors[tag] = #out
        table.insert(headings, { tag = tag, text = text, level = level, line = #out })
    end
    local function metadata(text)
        return (
            prose(text):gsub("|([^|%s]+)|", function(tag)
                return "[" .. tag .. "](rfc-tag:" .. tag .. ")"
            end)
        )
    end
    if model.kind == "rfc" then
        local function depth(number)
            local count = 0
            for _ in number:gmatch("[^.]+") do
                count = count + 1
            end
            return math.max(count, 1)
        end
        for _, block in ipairs(model.blocks) do
            local text = linked(block.text, block.mentions, function(m)
                return help.target(m, model.context, block.citation)
            end)
            if block.kind == "heading" then
                heading(model.tag_of[block], block.text, depth(block.section.number), text)
            else
                if block.kind == "row" then
                    local needle = block.section.label ~= "" and block.section.label or block.section.title
                    local first, last = text:find(needle, 1, true)
                    if first then
                        text = text:sub(1, first - 1)
                            .. "["
                            .. model.tag_of[block]
                            .. "](rfc-tag:"
                            .. model.tag_of[block]
                            .. ")"
                            .. text:sub(last + 1)
                    end
                end
                put(text)
                if block.kind == "reference" and model.tag_of[block] then
                    anchors[model.tag_of[block]] = #out
                end
            end
        end
        put("")
    elseif model.kind == "proposal" then
        for _, line in ipairs(model.header) do
            put(metadata(line))
        end
        put("")
        local function inline(text)
            return linked(text, model.spec.mentions(text), function(m)
                local tag = (m.kind or model.spec.prefix) .. (m.id or model.id)
                return m.section and tag .. "-" .. help.slug(m.section) or tag
            end)
        end
        if next(model.body.tags) then
            put("CONTENTS")
            for _, block in ipairs(model.blocks) do
                if block.kind == "heading" then
                    put(
                        string.rep("  ", block.level - model.body.top + 1)
                            .. "["
                            .. model.body.tags[block]
                            .. "](rfc-tag:"
                            .. model.body.tags[block]
                            .. ")  "
                            .. prose(block.title)
                    )
                end
            end
            put("")
        end
        for _, block in ipairs(model.blocks) do
            if block.kind == "heading" then
                heading(model.body.tags[block], model.body.texts[block], block.level)
            elseif block.kind == "fence" then
                local longest = 2
                for _, line in ipairs(block.code) do
                    local run = line:match("^ *(`+)")
                    longest = math.max(longest, run and #run or 0)
                end
                local mark = string.rep("`", longest + 1)
                put(mark .. (block.lang or ""))
                for _, line in ipairs(block.code) do
                    put(line)
                end
                put(mark)
            elseif block.kind == "table" then
                if block.caption then
                    put(prose(block.caption))
                end
                local width = 0
                for _, row in ipairs(block.rows) do
                    width = math.max(width, #row)
                end
                local function row(cells)
                    local rendered = {}
                    for i = 1, width do
                        rendered[i] = inline(cells[i] or ""):gsub("|", "\\|")
                    end
                    put("| " .. table.concat(rendered, " | ") .. " |")
                end
                if not block.header then
                    row({})
                end
                for i, cells in ipairs(block.rows) do
                    row(cells)
                    if i == 1 then
                        local rule = {}
                        for j = 1, width do
                            rule[j] = "---"
                        end
                        put("| " .. table.concat(rule, " | ") .. " |")
                    end
                end
            elseif block.kind == "notes" then
                for _, note in ipairs(block.notes) do
                    put("[" .. note.n .. "] " .. inline(note.text))
                end
            else
                put(inline(block.text))
            end
        end
        put("")
    elseif model.kind == "subjects" then
        put(prose(model.doc.about))
        put("")
        for _, node in ipairs(model.nodes) do
            put(
                string.rep("  ", #node.node.path - 1)
                    .. "["
                    .. node.tag
                    .. "](rfc-tag:"
                    .. node.tag
                    .. ")  "
                    .. prose(node.node.name)
                    .. " ("
                    .. node.count
                    .. ")"
            )
        end
        put("")
        for _, node in ipairs(model.nodes) do
            heading(node.tag, node.node.name .. "  (" .. node.count .. ")", #node.node.path)
            for _, entry in ipairs(node.node.entries) do
                local tag = model.doc.prefix .. (model.doc.key == "shortname" and "-" or "") .. entry.id
                put("[" .. tag .. "](rfc-tag:" .. tag .. ")  " .. prose(entry.label))
            end
            put("")
        end
    else
        error("unknown source model")
    end
    local doc = document.new(out, { anchors = anchors }) --[[@as rfc.Document]]
    doc.headings = headings
    return doc
end

---@param id string
---@param lines string[]
---@param url string
---@return rfc.Document
function M.report(id, lines, url)
    return M.from_model(require("rfc.help_w3c").model(id, lines, url))
end

return M

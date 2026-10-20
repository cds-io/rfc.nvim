-- An Ethereum proposal as a Vim help document. render is total: the
-- frontmatter becomes a header block, the headings get tags and a table of
-- contents of links, fenced code becomes help code blocks, tables become
-- aligned columns, inline HTML and emphasis become their text, and every
-- EIP or ERC the text names becomes a link. Nothing here touches the editor.
local eip = require("cds.eip")
local help = require("rfc.help")

local M = {}

---@param line string
---@return string
local function link(line)
    local mentions = eip.mentions(line)
    for i = #mentions, 1, -1 do
        local m = mentions[i]
        line = line:sub(1, m.first - 1) .. "|" .. m.kind .. m.id .. "|" .. line:sub(m.last + 1)
    end
    return line
end

--- A table as aligned columns: cells padded to their column, two spaces
--- apart, indented by two, and a rule of dashes under a heading row. No bar
--- survives, since help would read |cell| as a link.
---@param t cds.eip.Table
---@return string[]
local function layout(t)
    local widths = {}
    for _, row in ipairs(t.rows) do
        for c, cell in ipairs(row) do
            widths[c] = math.max(widths[c] or 0, #cell)
        end
    end
    local function line(cells)
        local padded = {}
        for c, width in ipairs(widths) do
            local cell = cells[c] or ""
            padded[c] = cell .. string.rep(" ", width - #cell)
        end
        return ("  " .. table.concat(padded, "  ")):gsub("%s+$", "")
    end
    local out = {}
    for r, row in ipairs(t.rows) do
        table.insert(out, (line(row)))
        if r == 1 and t.header then
            local rule = {}
            for c, width in ipairs(widths) do
                rule[c] = string.rep("-", width)
            end
            table.insert(out, (line(rule)))
        end
    end
    return out
end

--- The document for a proposal's text. Every proposal is tagged by its EIP
--- number; one in the ERC category also carries its ERC name, since the
--- texts of other proposals use both.
---@param id string
---@param lines string[]
---@return rfc.HelpDoc
function M.render(id, lines)
    local fields, body = eip.frontmatter(lines)
    local label = fields.category == "ERC" and "ERC" or "EIP"
    local file_tag = "eip" .. id
    local out, tags = {}, {}
    local function put(line)
        table.insert(out, line)
    end
    local function tag(name)
        table.insert(tags, { name = name, line = #out })
    end

    put(help.with_tag("*" .. file_tag .. ".txt*  " .. (fields.title or (label .. " " .. id)), file_tag))
    tag(file_tag)
    tag(file_tag .. ".txt")
    if fields.category == "ERC" then
        out[1] = out[1] .. " *erc" .. id .. "*"
        tag("erc" .. id)
    end
    local header = { label .. "-" .. id }
    for _, key in ipairs({ "status", "type", "category", "created" }) do
        if fields[key] then
            table.insert(header, key:sub(1, 1):upper() .. key:sub(2) .. ": " .. fields[key])
        end
    end
    put(table.concat(header, "  "))
    local requires = eip.requires(fields)
    if #requires > 0 then
        local links = {}
        for _, r in ipairs(requires) do
            table.insert(links, "|eip" .. r .. "|")
        end
        put("Requires: " .. table.concat(links, ", "))
    end
    if fields.author then
        put("Author: " .. fields.author)
    end
    if fields.status == "Moved" then
        put("Moved: see |erc" .. id .. "|")
    end
    put("")

    -- the body as blocks whose text is already plain; the render is one fold
    -- over them, a renderer per kind, so nothing below can skip that pass
    local blocks = eip.blocks(lines, body)
    local tag_of, used = {}, {}
    for _, b in ipairs(blocks) do
        if b.kind == "heading" then
            local name = file_tag .. "-" .. help.slug(b.title)
            if used[name] then
                used[name] = used[name] + 1
                name = name .. "-" .. used[name]
            else
                used[name] = 1
            end
            tag_of[b] = name
        end
    end
    if next(tag_of) then
        put("CONTENTS")
        for _, b in ipairs(blocks) do
            if b.kind == "heading" then
                put(string.rep("  ", math.max(b.level - 1, 1)) .. "|" .. tag_of[b] .. "|  " .. b.title)
            end
        end
        put("")
    end

    local render = {
        heading = function(b)
            return { help.with_tag(b.level <= 2 and b.title:upper() or b.title, tag_of[b]) }
        end,
        fence = function(b)
            local block = { ">" .. b.lang }
            for _, code in ipairs(b.code) do
                table.insert(block, "    " .. code)
            end
            table.insert(block, "<")
            return block
        end,
        table = layout,
        line = function(b)
            local text = link(b.text)
            -- a leading < would read as the end of a code block and vanish
            return { text:match("^<") and (" " .. text) or text }
        end,
    }
    for _, b in ipairs(blocks) do
        for _, line in ipairs(render[b.kind](b)) do
            put(line)
        end
        if b.kind == "heading" then
            tag(tag_of[b])
        end
    end
    put("")
    put(help.MODELINE)
    put(help.FOOTER)
    return { lines = out, tags = tags }
end

return M

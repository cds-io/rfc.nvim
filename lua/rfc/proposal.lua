-- The proposal render, over a declaration of what a source's proposals
-- look like: how the text reads into its fields and blocks, which fields
-- make the header and which name other proposals, how the text names a
-- proposal. The document is the same shape for every source: a title line
-- with the file tags, a header line, the rows the fields give, then the
-- body as one fold over the blocks with a contents block of links first.
-- A heading gets a tag of the file tag and its slug (numbered when a title
-- repeats), a fence becomes a help code block, a table aligned columns,
-- the notes a numbered list, and a line goes through the link pass.
-- Nothing here touches the editor.
local help = require("rfc.help")
local fp = require("cds.fp")

local M = {}

---@class rfc.ProposalRow
---@field key string                           -- the frontmatter field
---@field as "text"|"links"|fun(value: string): string[]  -- as written; the numbers as |prefixN| links; a list, joined with commas

---@class rfc.ProposalSpec
---@field prefix string                                -- the tag prefix: eip, bip, simd
---@field label fun(fields: table<string, string>): string   -- the title's fallback: "BIP 32" is label .. " " .. id
---@field number fun(fields: table<string, string>, id: string): string  -- the header's first cell: EIP-1559, SIMD-0064
---@field read fun(lines: string[]): table<string, string>, rfc.ProposalBlock[]  -- the fields and the body's blocks
---@field header string[]                              -- the fields the header line carries, in order
---@field rows (rfc.ProposalRow|fun(fields: table<string, string>, id: string): string|nil)[]  -- lines after the header, each when its field is set
---@field tags nil|fun(fields: table<string, string>, id: string): string[]  -- other names the file is tagged by: erc20 for an ERC
---@field mentions fun(line: string): cds.Mention[]    -- what the text names

---@param key string
---@return string
local function label(key)
    return key:sub(1, 1):upper() .. key:sub(2)
end

--- The numbers a field names, as links; nil when none.
---@param prefix string
---@param value string
---@return string|nil
function M.links(prefix, value)
    local out = {}
    for n in value:gmatch("%d+") do
        table.insert(out, "|" .. prefix .. n:gsub("^0+(%d)", "%1") .. "|")
    end
    return #out > 0 and table.concat(out, ", ") or nil
end

--- A row after the header: the field's label and its value in the form
--- asked; nil when the field is empty or names nothing.
---@param prefix string
---@param fields table<string, string>
---@param row rfc.ProposalRow
---@return string|nil
function M.row(prefix, fields, row)
    local value = fields[row.key]
    if not value or value == "" then
        return nil
    end
    local text
    if row.as == "links" then
        text = M.links(prefix, value)
    elseif type(row.as) == "function" then
        local items = row.as(value)
        text = #items > 0 and table.concat(items, ", ") or nil
    else
        text = value
    end
    return text and (label(row.key) .. ": " .. text) or nil
end

--- The link pass for a document: a mention becomes |kindN|, or
--- |kindN-section| when it names a section, the document's own prefix and
--- number standing in for what the mention leaves out (a link into the
--- document itself).
---@param spec rfc.ProposalSpec
---@param id string
---@return fun(line: string): string
function M.linker(spec, id)
    return function(line)
        local found = spec.mentions(line)
        for i = #found, 1, -1 do
            local m = found[i]
            local tag = (m.kind or spec.prefix) .. (m.id or id)
            if m.section then
                tag = tag .. "-" .. help.slug(m.section)
            end
            line = line:sub(1, m.first - 1) .. "|" .. tag .. "|" .. line:sub(m.last + 1)
        end
        return line
    end
end

--- The document for a proposal's text, total: an empty text gives the
--- title line, the header and the footer.
---@param spec rfc.ProposalSpec
---@param id string
---@param lines string[]
---@return rfc.HelpDoc
function M.render(spec, id, lines)
    local fields, blocks = spec.read(lines)
    local file_tag = spec.prefix .. id
    local out, tags = {}, {}
    local function put(line)
        table.insert(out, line)
    end
    local function tag(name)
        table.insert(tags, { name = name, line = #out })
    end

    put(help.with_tag("*" .. file_tag .. ".txt*  " .. (fields.title or (spec.label(fields) .. " " .. id)), file_tag))
    tag(file_tag)
    tag(file_tag .. ".txt")
    for _, name in ipairs(spec.tags and spec.tags(fields, id) or {}) do
        out[1] = out[1] .. " *" .. name .. "*"
        tag(name)
    end
    local set = fp.filter(spec.header, function(key)
        return fields[key] ~= nil and fields[key] ~= ""
    end)
    local header = fp.map(set, function(key)
        return label(key) .. ": " .. fields[key]
    end)
    table.insert(header, 1, spec.number(fields, id))
    put(table.concat(header, "  "))
    for _, row in ipairs(spec.rows) do
        local line
        if type(row) == "function" then
            line = row(fields, id)
        else
            line = M.row(spec.prefix, fields, row)
        end
        if line then
            put(line)
        end
    end
    put("")

    local body, body_tags = M.body(blocks, file_tag, M.linker(spec, id))
    local offset = #out
    for _, line in ipairs(body) do
        put(line)
    end
    for _, t in ipairs(body_tags) do
        table.insert(tags, { name = t.name, line = offset + t.line })
    end
    put("")
    put(help.MODELINE)
    put(help.FOOTER)
    return { lines = out, tags = tags }
end

--- A table as aligned columns: its caption on a line of its own, cells
--- padded to their column, two spaces apart, indented by two, and a rule
--- of dashes under a heading row. No bar survives, since help would read
--- |cell| as a link.
---@param t { caption: string|nil, header: boolean, rows: string[][] }
---@return string[]
function M.layout(t)
    local widths = {}
    for _, row in ipairs(t.rows) do
        for c, cell in ipairs(row) do
            widths[c] = math.max(widths[c] or 0, #cell)
        end
    end
    local function line(cells)
        local padded = fp.map(widths, function(width, c)
            local cell = cells[c] or ""
            return cell .. string.rep(" ", width - #cell)
        end)
        return ("  " .. table.concat(padded, "  ")):gsub("%s+$", "")
    end
    local out = fp.map(t.rows, function(row)
        return (line(row))
    end)
    if t.header and #out > 0 then
        local rule = fp.map(widths, function(width)
            return string.rep("-", width)
        end)
        table.insert(out, 2, (line(rule)))
    end
    if t.caption then
        table.insert(out, 1, "  " .. t.caption)
    end
    return out
end

---@class rfc.ProposalBlock
---@field kind "heading"|"fence"|"table"|"notes"|"line"
---@field level integer|nil
---@field title string|nil
---@field lang string|nil
---@field code string[]|nil
---@field header boolean|nil
---@field rows string[][]|nil
---@field notes { n: integer, text: string }[]|nil
---@field text string|nil

--- The body: a CONTENTS block of the headings as links, indented by level
--- from the shallowest heading, then every block rendered. Level one and
--- two headings are written in capitals. Answers the lines and the tags
--- they carry, each tag's line counted from 1 within the lines answered.
---@param blocks rfc.ProposalBlock[]
---@param file_tag string
---@param link fun(text: string): string   -- the render's link pass over a line
---@return string[] lines
---@return rfc.HelpTag[] tags
function M.body(blocks, file_tag, link)
    local out, tags = {}, {}
    local function put(line)
        table.insert(out, line)
    end
    local tag_of, used, top = {}, {}, nil
    for _, b in ipairs(blocks) do
        if b.kind == "heading" then
            top = math.min(top or b.level, b.level)
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
                put(string.rep("  ", b.level - top + 1) .. "|" .. tag_of[b] .. "|  " .. b.title)
            end
        end
        put("")
    end

    local render = {
        heading = function(b)
            return { help.with_tag(b.level <= 2 and b.title:upper() or b.title, tag_of[b]) }
        end,
        fence = function(b)
            local block = fp.map(b.code, function(code)
                return "    " .. code
            end)
            table.insert(block, 1, ">" .. b.lang)
            table.insert(block, "<")
            return block
        end,
        table = M.layout,
        notes = function(b)
            return fp.map(b.notes, function(note)
                return "[" .. note.n .. "] " .. link(note.text)
            end)
        end,
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
            table.insert(tags, { name = tag_of[b], line = #out })
        end
    end
    return out, tags
end

return M

---@class rfc.ProposalPlan
---@field tags table<rfc.ProposalBlock, string>
---@field texts table<rfc.ProposalBlock, string>
---@field top integer

---@class rfc.ProposalModel
---@field kind "proposal"
---@field name string
---@field title string
---@field id string
---@field fields table<string, string>
---@field blocks rfc.ProposalBlock[]
---@field aliases string[]
---@field header rfc.Inline[]
---@field inlines table<string, rfc.Inline>
---@field body rfc.ProposalPlan

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
---@field rows (rfc.ProposalRow|fun(fields: table<string, string>, id: string): rfc.Inline|string|nil)[]  -- lines after the header, each when its field is set
---@field tags nil|fun(fields: table<string, string>, id: string): string[]  -- other names the file is tagged by: erc20 for an ERC
---@field mentions fun(line: string): rfc.source.Mention[]    -- what the text names

---@param key string
---@return string
local function label(key)
    return key:sub(1, 1):upper() .. key:sub(2)
end

---@class rfc.InlinePart
---@field text string
---@field target? string -- application tag, without help or Markdown delimiters

---@alias rfc.Inline rfc.InlinePart[]

--- Render resolved text/link parts without interpreting literal text as markup.
--- Plain text is transformed as one string, keeping inline code spans intact.
---@param parts rfc.Inline
---@param link fun(target: string): string
---@param plain? fun(text: string): string
---@return string
function M.format(parts, link, plain)
    local out = {}
    for i, part in ipairs(parts) do
        out[i] = part.target and ("\1" .. i .. "\2") or part.text
    end
    local text = table.concat(out)
    text = plain and plain(text) or text
    return (text:gsub("\1(%d+)\2", function(index)
        return link(parts[tonumber(index)].target)
    end))
end

---@param target string
---@return string
local function help_link(target)
    return "|" .. target .. "|"
end

--- The tag a source mention names, resolved once while preparing the model.
---@param spec rfc.ProposalSpec
---@param id string
---@param mention rfc.source.Mention
---@return string
local function target(spec, id, mention)
    local tag = (mention.kind or spec.prefix) .. (mention.id or id)
    return mention.section and (tag .. "-" .. help.slug(mention.section)) or tag
end

--- Literal text and resolved links, in source order.
---@param spec rfc.ProposalSpec
---@param id string
---@param text string
---@return rfc.Inline
function M.inline(spec, id, text)
    local out, from = {}, 1
    for _, mention in ipairs(spec.mentions(text)) do
        if mention.first > from then
            out[#out + 1] = { text = text:sub(from, mention.first - 1) }
        end
        out[#out + 1] = { text = text:sub(mention.first, mention.last), target = target(spec, id, mention) }
        from = mention.last + 1
    end
    if from <= #text then
        out[#out + 1] = { text = text:sub(from) }
    end
    return out
end

---@param prefix string
---@param value string
---@return rfc.Inline
local function number_links(prefix, value)
    local out = {}
    for n in value:gmatch("%d+") do
        if #out > 0 then
            out[#out + 1] = { text = ", " }
        end
        local tag = prefix .. n:gsub("^0+(%d)", "%1")
        out[#out + 1] = { text = tag, target = tag }
    end
    return out
end

--- Compatibility export of a numeric field as help links.
---@param prefix string
---@param value string
---@return string?
function M.links(prefix, value)
    local parts = number_links(prefix, value)
    return #parts > 0 and M.format(parts, help_link) or nil
end

---@param prefix string
---@param fields table<string, string>
---@param row rfc.ProposalRow
---@return rfc.Inline?
local function row_parts(prefix, fields, row)
    local value = fields[row.key]
    if not value or value == "" then
        return nil
    end
    local parts
    if row.as == "links" then
        parts = number_links(prefix, value)
    elseif type(row.as) == "function" then
        local items = row.as(value)
        parts = #items > 0 and { { text = table.concat(items, ", ") } } or {}
    else
        parts = { { text = value } }
    end
    if #parts == 0 then
        return nil
    end
    table.insert(parts, 1, { text = label(row.key) .. ": " })
    return parts
end

--- Compatibility export of a header row as help text.
---@param prefix string
---@param fields table<string, string>
---@param row rfc.ProposalRow
---@return string?
function M.row(prefix, fields, row)
    local parts = row_parts(prefix, fields, row)
    return parts and M.format(parts, help_link) or nil
end

--- Compatibility helper; shared model consumers use pre-resolved inline parts.
---@param spec rfc.ProposalSpec
---@param id string
---@return fun(line: string): string
function M.linker(spec, id)
    return function(line)
        return M.format(M.inline(spec, id, line), help_link)
    end
end

--- The document for a proposal's text, total: an empty text gives the
--- title line, the header and the footer.
---@param spec rfc.ProposalSpec
---@param id string
---@param lines string[]
---@return rfc.ProposalModel
function M.model(spec, id, lines)
    local fields, blocks = spec.read(lines)
    local name = spec.prefix .. id
    local header = fp.map(
        fp.filter(spec.header, function(key)
            return fields[key] ~= nil and fields[key] ~= ""
        end),
        function(key)
            return label(key) .. ": " .. fields[key]
        end
    )
    table.insert(header, 1, spec.number(fields, id))
    local rows = { { { text = table.concat(header, "  ") } } }
    for _, row in ipairs(spec.rows) do
        local line = type(row) == "function" and row(fields, id)
            or type(row) == "table" and row_parts(spec.prefix, fields, row)
        if line then
            table.insert(rows, type(line) == "string" and { { text = line } } or line)
        end
    end
    local inlines = { [""] = {} }
    local function prepare(text)
        if text and not inlines[text] then
            inlines[text] = M.inline(spec, id, text)
        end
    end
    for _, block in ipairs(blocks) do
        prepare(block.text)
        for _, cells in ipairs(block.rows or {}) do
            for _, cell in ipairs(cells) do
                prepare(cell)
            end
        end
        for _, note in ipairs(block.notes or {}) do
            prepare(note.text)
        end
    end
    return {
        kind = "proposal",
        name = name,
        id = id,
        blocks = blocks,
        title = fields.title or (spec.label(fields) .. " " .. id),
        fields = fields,
        aliases = spec.tags and spec.tags(fields, id) or {},
        header = rows,
        inlines = inlines,
        body = M.plan_body(blocks, name),
    }
end

---@param spec rfc.ProposalSpec
---@param id string
---@param lines string[]
---@return rfc.HelpDoc
function M.render(spec, id, lines)
    return M.render_model(M.model(spec, id, lines))
end

---@param model rfc.ProposalModel
---@return rfc.HelpDoc
function M.render_model(model)
    local blocks, file_tag = model.blocks, model.name
    local out, tags = {}, {}
    local function put(line)
        table.insert(out, line)
    end
    local function tag(name)
        table.insert(tags, { name = name, line = #out })
    end

    put(help.with_tag("*" .. file_tag .. ".txt*  " .. model.title, file_tag))
    tag(file_tag)
    tag(file_tag .. ".txt")
    for _, name in ipairs(model.aliases) do
        out[1] = out[1] .. " *" .. name .. "*"
        tag(name)
    end
    for _, line in ipairs(model.header) do
        put(M.format(line, help_link))
    end
    put("")

    local body, body_tags = M.body(blocks, file_tag, function(text)
        return M.format(model.inlines[text], help_link)
    end, model.body)
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
    return { lines = out, tags = tags, model = model }
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
---@field caption string|nil
---@field header boolean|nil
---@field rows string[][]|nil
---@field notes { n: integer, text: string }[]|nil
---@field text string|nil

--- Heading identity is planned once for both renderers.
---@param blocks rfc.ProposalBlock[]
---@param file_tag string
---@return rfc.ProposalPlan
function M.plan_body(blocks, file_tag)
    local tag_of, used, texts, top = {}, {}, {}, nil
    for _, b in ipairs(blocks) do
        if b.kind == "heading" then
            local level = assert(b.level, "a heading carries its level")
            top = math.min(top or level, level)
            local base = file_tag .. "-" .. help.slug(b.title)
            local name, n = base, 1
            while used[name] do
                n = n + 1
                name = base .. "-" .. n
            end
            used[name] = true
            tag_of[b] = name
            texts[b] = b.level <= 2 and b.title:upper() or b.title
        end
    end
    return { tags = tag_of, texts = texts, top = top or 1 }
end

--- The body: a CONTENTS block of the headings as links, indented by level
--- from the shallowest heading, then every block rendered. Level one and
--- two headings are written in capitals. Answers the lines and the tags
--- they carry, each tag's line counted from 1 within the lines answered.
---@param blocks rfc.ProposalBlock[]
---@param file_tag string
---@param link fun(text: string): string   -- the render's link pass over a line
---@param plan? rfc.ProposalPlan
---@return string[] lines
---@return rfc.HelpTag[] tags
function M.body(blocks, file_tag, link, plan)
    local out, tags = {}, {}
    local function put(line)
        table.insert(out, line)
    end
    local prepared = plan or M.plan_body(blocks, file_tag)
    local tag_of, top = prepared.tags, prepared.top
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
            return { help.with_tag(prepared.texts[b], tag_of[b]) }
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

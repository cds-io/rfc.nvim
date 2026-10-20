-- The RFC as a Vim help document. render is total: whatever the text, it
-- answers a document and the tags that name its headings, so a reader can
-- `:help rfc9110-3.1`, follow |links| with CTRL-] and come back with CTRL-T.
-- Nothing here touches the editor; the store writes the document and the
-- tags file, and `:help` does the rest.
local rfc = require("cds.rfc")

local M = {}

---@class rfc.HelpTag
---@field name string
---@field line integer   -- the line of the rendered document the tag sits on

---@class rfc.HelpDoc
---@field lines string[]
---@field tags rfc.HelpTag[]

-- Help files wrap at 78; the tag on a heading ends there when the heading
-- leaves room, and sits one space after it otherwise.
local WIDTH = 78
local MODELINE = " vim:tw=78:ts=8:ft=help:norl:"

-- The render's version, written as the document's last line. A cached
-- document whose line names an older version is rendered again from the
-- stored text, so a better render reaches what is already on disk.
M.RENDER = 5
M.FOOTER = " rfc.nvim render " .. M.RENDER

--- The render version a document's last line names, 0 when it names none.
---@param lines string[]
---@return integer
function M.render_of(lines)
    local last = lines[#lines] or ""
    return tonumber(last:match("^ rfc%.nvim render (%d+)$")) or 0
end

--- Lowercase, with every run of characters outside [%w.-] collapsed to one
--- dash, so a title or a citation key spells a tag the help tag scanner
--- and the search command both accept.
---@param s string
---@return string
function M.slug(s)
    local out = s:lower():gsub("[^%w%.%-]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    return out
end
local slug = M.slug

--- The tag for a section: `rfc9110-3.1` for "3.1", `rfc9110-A` for appendix
--- A, and the slugged title for a part with no number (Index).
---@param rfc_num string
---@param number string
---@param title string
---@return string
function M.tag(rfc_num, number, title)
    return "rfc" .. rfc_num .. "-" .. (number ~= "" and number or slug(title))
end

--- The tag for an entry in the references: `rfc9110-ref-CACHING` for
--- "[CACHING]"; the case is kept because that is how the RFC spells it.
---@param rfc_num string
---@param citation string   -- with its brackets
---@return string
function M.ref_tag(rfc_num, citation)
    local key = citation:gsub("^%[", ""):gsub("%]$", ""):gsub("[^%w%.%-]+", "-")
    return "rfc" .. rfc_num .. "-ref-" .. key
end

--- The RFC's title: the centred lines after the header block. The header
--- block is the first run of column-0 lines; the title is the first run of
--- indented lines after the blank that ends it.
---@param lines string[]
---@return string|nil
function M.title(lines)
    local i = 1
    while lines[i] and not lines[i]:match("^%S") do
        i = i + 1
    end
    while lines[i] and lines[i]:match("%S") do
        i = i + 1
    end
    while lines[i] and not lines[i]:match("%S") do
        i = i + 1
    end
    local words = {}
    while lines[i] and lines[i]:match("^%s+%S") do
        table.insert(words, (lines[i]:match("^%s*(.-)%s*$")))
        i = i + 1
    end
    if #words == 0 then
        return nil
    end
    return table.concat(words, " ")
end

--- A fetched body as lines: form feeds and the byte-order mark removed,
--- CRLF folded, the final newline dropped.
---@param body string
---@return string[]
function M.clean(body)
    body = body:gsub("\239\187\191", ""):gsub("\f", ""):gsub("\r\n", "\n"):gsub("\n$", "")
    local lines = {}
    for line in (body .. "\n"):gmatch("(.-)\n") do
        table.insert(lines, line)
    end
    return lines
end

--- The line with `*tag*` ending at column 78, or one space after the
--- line when it leaves no room.
---@param line string
---@param tag string
---@return string
function M.with_tag(line, tag)
    local star = "*" .. tag .. "*"
    local pad = WIDTH - #line - #star
    return line .. string.rep(" ", math.max(pad, 1)) .. star
end
local with_tag = M.with_tag
M.MODELINE = MODELINE

--- Replaces the first plain occurrence of `needle` in `line` with `repl`.
---@param line string
---@param needle string
---@param repl string
---@return string
local function replace_first(line, needle, repl)
    local first, last = line:find(needle, 1, true)
    if not first then
        return line
    end
    return line:sub(1, first - 1) .. repl .. line:sub(last + 1)
end

--- The context a body line is rewritten in.
---@class rfc.help.Context
---@field rfc_num string
---@field known table<string, boolean>   -- section tags this document defines
---@field ref_tags table<string, string> -- citation (with brackets) -> its ref tag
---@field cite_rfc fun(citation: string): string|nil

--- The tag a mention links to, or nil when it has none: a same-document
--- section links only when its heading was found, since a link to nothing
--- is a dead end; a citation only when the references list it, and never
--- the one a reference entry is defining on that line.
---@param m cds.rfc.Mention
---@param ctx rfc.help.Context
---@param own? string   -- the citation the line defines, if it is a reference entry
---@return string|nil
local function tag_for(m, ctx, own)
    if m.kind == "rfc" then
        return "rfc" .. m.rfc
    elseif m.kind == "citation" then
        return m.citation ~= own and ctx.ref_tags[m.citation] or nil
    end
    local target = m.rfc or (m.citation and ctx.cite_rfc(m.citation))
    if target then
        return "rfc" .. target .. "-" .. m.number
    end
    local here = "rfc" .. ctx.rfc_num .. "-" .. m.number
    return ctx.known[here] and here or nil
end

--- A block's text with every mention replaced by its link, last to first
--- so the earlier spans stay where the reader found them.
---@param b cds.rfc.Block
---@param ctx rfc.help.Context
---@return string
local function link(b, ctx)
    local line = b.text
    for i = #b.mentions, 1, -1 do
        local m = b.mentions[i]
        local tag = tag_for(m, ctx, b.citation)
        if tag then
            line = line:sub(1, m.first - 1) .. "|" .. tag .. "|" .. line:sub(m.last + 1)
        end
    end
    return line
end

--- The document for an RFC's text: one fold over the reader's blocks.
--- Every block links what it names, then gets its kind's decoration: the
--- tag on a heading or a reference entry, the row link on a ToC row; a
--- page header is left as written.
---@param rfc_num string
---@param lines string[]
---@return rfc.HelpDoc
function M.render(rfc_num, lines)
    local blocks = rfc.blocks(lines)
    local file_tag = "rfc" .. rfc_num
    local tag_of, known, ref_tags, entry_at = {}, {}, {}, {}
    for _, b in ipairs(blocks) do
        if b.kind == "heading" or b.kind == "row" then
            local tag = M.tag(rfc_num, b.section.number, b.section.title)
            tag_of[b] = tag
            known[tag] = true
        elseif b.kind == "reference" then
            entry_at[b.citation] = b.line
            if not b.citation:match("^%[RFC%d+%]$") then
                tag_of[b] = M.ref_tag(rfc_num, b.citation)
                ref_tags[b.citation] = tag_of[b]
            end
        end
    end
    local ctx = {
        rfc_num = rfc_num,
        known = known,
        ref_tags = ref_tags,
        cite_rfc = function(citation)
            return entry_at[citation] and rfc.cited_rfc(lines, entry_at[citation])
        end,
    }

    local decorate = {
        header = function(b)
            return b.text
        end,
        heading = function(b)
            return with_tag(link(b, ctx), tag_of[b])
        end,
        row = function(b)
            local needle = b.section.label ~= "" and b.section.label or b.section.title
            return replace_first(link(b, ctx), needle, "|" .. tag_of[b] .. "|")
        end,
        reference = function(b)
            local text = link(b, ctx)
            return tag_of[b] and with_tag(text, tag_of[b]) or text
        end,
        line = function(b)
            return link(b, ctx)
        end,
    }

    local title = M.title(lines) or ("RFC " .. rfc_num)
    local out = { with_tag("*" .. file_tag .. ".txt*  " .. title, file_tag) }
    local tags = { { name = file_tag, line = 1 }, { name = file_tag .. ".txt", line = 1 } }
    for _, b in ipairs(blocks) do
        table.insert(out, decorate[b.kind](b))
        if tag_of[b] and b.kind ~= "row" then
            table.insert(tags, { name = tag_of[b], line = #out })
        end
    end
    table.insert(out, "")
    table.insert(out, MODELINE)
    table.insert(out, M.FOOTER)
    return { lines = out, tags = tags }
end

--- The tags a rendered document carries: every `*tag*` whose name is a
--- source prefix and a number (rfc9110, eip1559-abstract, erc20.txt), which
--- is the shape every render declares and no text contains by accident. The
--- store reads every document back through this to rebuild the tags file.
---@param lines string[]
---@return rfc.HelpTag[]
function M.tags_in(lines)
    local tags = {}
    for i, line in ipairs(lines) do
        for name in line:gmatch("%*(%l%l%l%d[%w%.%-]*)%*") do
            table.insert(tags, { name = name, line = i })
        end
    end
    return tags
end

--- The lines of a help tags file for the documents given, byte-sorted as
--- Vim's tag search expects. The search command is the tag between stars,
--- which only a heading carries; stray stars in an RFC's text never enter
--- this file, which is why the file is written here and not by :helptags.
---@param docs { file: string, tags: rfc.HelpTag[] }[]
---@return string[]
function M.tags_file(docs)
    local lines = {}
    for _, doc in ipairs(docs) do
        for _, tag in ipairs(doc.tags) do
            table.insert(lines, tag.name .. "\t" .. doc.file .. "\t/*" .. tag.name .. "*")
        end
    end
    table.sort(lines)
    return lines
end

return M

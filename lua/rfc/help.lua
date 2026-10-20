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

--- Lowercase, with every run of characters outside [%w.-] collapsed to one
--- dash, so a title or a citation key spells a tag the help tag scanner
--- and the search command both accept.
---@param s string
---@return string
local function slug(s)
    local out = s:lower():gsub("[^%w%.%-]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    return out
end

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

---@param line string
---@param tag string
---@return string
local function with_tag(line, tag)
    local star = "*" .. tag .. "*"
    local pad = WIDTH - #line - #star
    return line .. string.rep(" ", math.max(pad, 1)) .. star
end

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
--- is a dead end; a citation only when the references list it.
---@param m cds.rfc.Mention
---@param ctx rfc.help.Context
---@return string|nil
local function tag_for(m, ctx)
    if m.kind == "rfc" then
        return "rfc" .. m.rfc
    elseif m.kind == "citation" then
        return ctx.ref_tags[m.citation]
    end
    local target = m.rfc or (m.citation and ctx.cite_rfc(m.citation))
    if target then
        return "rfc" .. target .. "-" .. m.number
    end
    local own = "rfc" .. ctx.rfc_num .. "-" .. m.number
    return ctx.known[own] and own or nil
end

--- Every mention on the line replaced by its link, last to first so the
--- earlier spans stay where they were found.
---@param line string
---@param ctx rfc.help.Context
---@return string
local function link(line, ctx)
    local mentions = rfc.mentions(line)
    for i = #mentions, 1, -1 do
        local m = mentions[i]
        local tag = tag_for(m, ctx)
        if tag then
            line = line:sub(1, m.first - 1) .. "|" .. tag .. "|" .. line:sub(m.last + 1)
        end
    end
    return line
end

--- The document for an RFC's text.
---@param rfc_num string
---@param lines string[]
---@return rfc.HelpDoc
function M.render(rfc_num, lines)
    local sections = rfc.contents(lines)
    local file_tag = "rfc" .. rfc_num
    local heading_tag, row_link, known = {}, {}, {}
    for _, s in ipairs(sections) do
        local tag = M.tag(rfc_num, s.number, s.title)
        heading_tag[s.line] = tag
        row_link[s.toc_line] = { needle = s.label ~= "" and s.label or s.title, tag = tag }
        known[tag] = true
    end
    local references = rfc.references(lines, sections)
    local ref_tag_at, ref_tags = {}, {}
    for citation, i in pairs(references.entries) do
        if not citation:match("^%[RFC%d+%]$") then
            local tag = M.ref_tag(rfc_num, citation)
            ref_tag_at[i] = tag
            ref_tags[citation] = tag
        end
    end
    local ctx = {
        rfc_num = rfc_num,
        known = known,
        ref_tags = ref_tags,
        cite_rfc = function(citation)
            local entry = references.entries[citation]
            return entry and rfc.cited_rfc(lines, entry)
        end,
    }

    local title = M.title(lines) or ("RFC " .. rfc_num)
    local out = { with_tag("*" .. file_tag .. ".txt*  " .. title, file_tag) }
    local tags = { { name = file_tag, line = 1 }, { name = file_tag .. ".txt", line = 1 } }
    for i, line in ipairs(lines) do
        if heading_tag[i] then
            line = with_tag(line, heading_tag[i])
            table.insert(tags, { name = heading_tag[i], line = i + 1 })
        elseif row_link[i] then
            line = replace_first(line, row_link[i].needle, "|" .. row_link[i].tag .. "|")
        elseif ref_tag_at[i] then
            line = with_tag(line, ref_tag_at[i])
            table.insert(tags, { name = ref_tag_at[i], line = i + 1 })
        elseif not line:match("^RFC%s*%d+") then
            -- a page header names the RFC on every page; everything else may link
            line = link(line, ctx)
        end
        table.insert(out, line)
    end
    table.insert(out, "")
    table.insert(out, MODELINE)
    return { lines = out, tags = tags }
end

--- The tags a rendered document carries: the file tag on its first line and
--- the tag at the end of every heading and reference entry. The store reads
--- every document back through this to rebuild the tags file.
---@param lines string[]
---@return rfc.HelpTag[]
function M.tags_in(lines)
    local tags = {}
    local file_tag = lines[1] and lines[1]:match("^%*(rfc%d+%.txt)%*")
    if file_tag then
        table.insert(tags, { name = file_tag, line = 1 })
    end
    for i, line in ipairs(lines) do
        local name = line:match("%*(rfc%d[^%s%*]*)%*$")
        if name then
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

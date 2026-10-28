-- Reads Bitcoin improvement proposals. `preamble` reads the header of
-- `Key: value` lines; `format` says whether the body is MediaWiki or
-- markdown. For a MediaWiki body, `headings`, `code`, `tables` and
-- `footnotes` read their parts, `plain` and `unlink` turn the inline markup
-- into text, and `blocks` folds everything into the one list a renderer
-- walks; a markdown body is rfc.source.eip's. `mentions` finds the proposals a line
-- names, and `index` reads the repository's README table as entries. Every
-- function takes lines and answers tables, so the specs run under plain
-- busted.
local mentions = require("rfc.source.mentions")

---@class rfc.source.bip
local M = {}

---@class rfc.source.bip.Heading
---@field level integer   -- 1 for ==Title==, 2 for ===Title===, and so on
---@field title string    -- plain
---@field line integer

---@class rfc.source.bip.Code
---@field first integer   -- the line with the opening tag
---@field last integer    -- the line with the closing tag, or the last line when unterminated
---@field lang string     -- <source lang="x">: x; <pre>: ""
---@field code string[]   -- the lines between the tags, text sharing a line with a tag included

---@class rfc.source.bip.Table
---@field first integer
---@field last integer
---@field caption string|nil -- a |+ line, or a one-cell ! row spanning columns, before the rows
---@field header boolean  -- whether the first row's cells were written with !
---@field rows string[][] -- each row's cells, plain

---@class rfc.source.bip.Note
---@field n integer
---@field text string     -- plain

---@class rfc.source.bip.Mention
---@field kind "bip"
---@field id string|nil       -- the number without leading zeros; nil for a link into the document itself
---@field section string|nil  -- the anchor a link names, when it names one
---@field first integer       -- byte range of the text a link would replace
---@field last integer

---@class rfc.source.bip.Block
---@field kind "heading"|"fence"|"table"|"notes"|"line"
---@field line integer
---@field level integer|nil    -- heading
---@field title string|nil     -- heading: plain
---@field lang string|nil      -- fence
---@field code string[]|nil    -- fence: as written
---@field caption string|nil   -- table
---@field header boolean|nil   -- table
---@field rows string[][]|nil  -- table: plain
---@field notes rfc.source.bip.Note[]|nil  -- notes: every footnote of the text
---@field text string|nil      -- line: plain

---@class rfc.source.bip.Entry
---@field id string
---@field title string
---@field status string
---@field type string
---@field layer string

local header = require("rfc.source.bip.header")
local inline = require("rfc.source.bip.inline")
local structure = require("rfc.source.bip.structure")
local tables = require("rfc.source.bip.tables")
M.format, M.preamble = header.format, header.preamble
M.plain, M.unlink = inline.plain, inline.unlink
M.code, M.headings = structure.code, structure.headings
M.tables, M.index = tables.tables, tables.index
M.footnotes = require("rfc.source.bip.notes").footnotes

---@param id string
---@return string
local function number(id)
    return (id:gsub("^0+(%d)", "%1"))
end

---@param id string
---@param section string|nil
---@return table
local function named(id, section)
    return { kind = "bip", id = number(id), section = section }
end

---@param section string
---@return table
local function own(section)
    return { kind = "bip", section = section }
end

--- Finds every proposal a line names, in order of position: a wiki link
--- ([[bip-0032.mediawiki|BIP 32]], with a section after #), a link into the
--- document itself ([[#anchor|text]]), a markdown link
--- ([BIP 2](bip-0002.mediawiki)), and a bare BIP 32, BIP-32, BIP-0032, BIP32
--- or BIP0032 outside those. Numbers lose their leading zeros.
---@param line string
---@return rfc.source.bip.Mention[]
function M.mentions(line)
    return mentions.scan(line, {
        { "%[%[bip%-(%d+)%.%a+#?([%w%-_]*)|[^%]]*%]%]", named },
        { "%[%[#([%w%-_]+)|[^%]]*%]%]", own },
        { "%[[^%]]*%]%(bip%-(%d+)%.%a+#?([%w%-_]*)%)", named },
    }, { "BIP[%- ]?0*(%d+)", named })
end

--- Folds the body into blocks, every piece of text already plain: a heading, a
--- code block (as a fence, the shape a renderer walks), a table, the notes
--- where <references /> stands, or one line. The footnotes are replaced first,
--- so a line carries its markers. Lines in `omit` (the preamble) are left out.
---@param lines string[]
---@param omit? { first: integer, last: integer }
---@return rfc.source.bip.Block[]
function M.blocks(lines, omit)
    local text, notes = M.footnotes(lines)
    local code_at, table_at, skip = {}, {}, {}
    for _, c in ipairs(M.code(text)) do
        code_at[c.first] = c
        for i = c.first, c.last do
            skip[i] = true
        end
    end
    for _, t in ipairs(M.tables(text)) do
        table_at[t.first] = t
        for i = t.first, t.last do
            skip[i] = true
        end
    end
    local heading_at = {}
    for _, h in ipairs(M.headings(text)) do
        heading_at[h.line] = h
    end
    local function block(i, line)
        if omit and i >= omit.first and i <= omit.last then
            return nil
        elseif code_at[i] then
            return { kind = "fence", line = i, lang = code_at[i].lang, code = code_at[i].code }
        elseif table_at[i] then
            local t = table_at[i]
            return { kind = "table", line = i, caption = t.caption, header = t.header, rows = t.rows }
        elseif heading_at[i] then
            return { kind = "heading", line = i, level = heading_at[i].level, title = heading_at[i].title }
        elseif line:match("^%s*<references%s*/>%s*$") then
            return { kind = "notes", line = i, notes = notes }
        elseif not skip[i] then
            return { kind = "line", line = i, text = M.plain(line) }
        end
    end
    local blocks = {}
    for i, line in ipairs(text) do
        local b = block(i, line)
        if b then
            table.insert(blocks, b)
        end
    end
    return blocks
end

return M

-- Reads Ethereum improvement proposals. `frontmatter` reads the YAML header
-- into one string per field and says where the body starts; EIP-1 opens with
--
--   ---
--   eip: 1
--   title: EIP Purpose and Guidelines
--   status: Living
--   type: Meta
--   author: Martin Becze <mb@ethereum.org>, Hudson Jameson <hudson@ethereum.org>, et al.
--   created: 2015-10-27
--   ---
--
-- and comes back as `{ eip = "1", title = "EIP Purpose and Guidelines", ... }`
-- with the body starting on line 9. `headings`, `fences` and `tables` read
-- the markdown body, and `blocks` folds them into the one list a renderer
-- walks; `plain` turns a line's inline markup into text. `mentions` finds the
-- EIPs and ERCs a line names, and `requires` the numbers a `requires:` field
-- names. `listing` reads eips.ethereum.org/all (or the ERC site's page) as
-- entries. Every function takes lines and answers tables, so the specs run
-- under plain busted.

---@class rfc.source.eip
local M = {}

---@class rfc.source.eip.Heading
---@field level integer   -- the number of # signs
---@field title string
---@field line integer

---@class rfc.source.eip.Fence
---@field first integer   -- the opening ``` line
---@field last integer    -- the closing ``` line, or the last line when unterminated
---@field lang string     -- the info string after the fence, "" when none

---@class rfc.source.eip.Mention
---@field kind "eip"|"erc"
---@field first integer   -- byte range of the text a link would replace
---@field last integer
---@field id string

---@class rfc.source.eip.Table
---@field first integer      -- the first line of the table in the text
---@field last integer       -- the last
---@field header boolean     -- whether the first row is a heading row
---@field rows string[][]    -- each row's cells, as plain text

---@class rfc.source.eip.Block
---@field kind "heading"|"fence"|"table"|"line"
---@field line integer        -- the block's first line in the text
---@field level integer|nil   -- heading: the number of # signs
---@field title string|nil    -- heading: the title, plain
---@field lang string|nil     -- fence: the info string, "" when none
---@field code string[]|nil   -- fence: the lines between the fences, as written
---@field header boolean|nil  -- table: whether the first row is a heading row
---@field rows string[][]|nil -- table: the cells, plain
---@field text string|nil     -- line: the line, plain; "" for a blank line

---@class rfc.source.eip.Entry
---@field id string
---@field title string
---@field status string   -- the listing's section: "Final", "Draft", ...
---@field category string -- the page's title: "Core", "ERC", "All"; "" before any

local inline = require("rfc.source.eip.inline")
local structure = require("rfc.source.eip.structure")
M.frontmatter, M.fences, M.headings = structure.frontmatter, structure.fences, structure.headings
M.plain, M.mentions, M.requires, M.listing = inline.plain, inline.mentions, inline.requires, inline.listing
M.tables = require("rfc.source.eip.tables").tables

--- Numbers ordered lists as markdown means them: a run of items at one indent
--- (`1. a`, blank lines between items allowed) counts up from the first item's
--- number, whatever the author wrote on the rest, so a list written as `1. 1.
--- 1.` reads 1, 2, 3. A nested list counts on its own by its indent; an item at
--- a shallower indent ends the deeper runs. Any other line, or any block that
--- is no line, ends every run: a continuation paragraph indented under an item
--- ends it too, which leaves such a list as the author wrote it.
---@param blocks rfc.source.eip.Block[]
---@return rfc.source.eip.Block[]
local function number_lists(blocks)
    local runs = {} -- indent -> the next number
    for _, b in ipairs(blocks) do
        local indent, tail = nil, nil
        if b.kind == "line" then
            indent, tail = b.text:match("^(%s*)%d+(%.%s.*)$")
        end
        if indent then
            local width = #indent
            for deeper in pairs(runs) do
                if deeper > width then
                    runs[deeper] = nil
                end
            end
            local n = runs[width] or tonumber(b.text:match("^%s*(%d+)"))
            b.text = indent .. n .. tail
            runs[width] = n + 1
        elseif b.kind ~= "line" or b.text ~= "" then
            runs = {}
        end
    end
    return blocks
end

--- Folds the body into blocks, every piece of text already plain: a heading, a
--- fenced code block, a table, or one line, with ordered lists numbered. A
--- renderer walks this list, so no kind of text can miss the plain-text pass.
---@param lines string[]
---@param from? integer   -- the first body line; 1 unless given
---@return rfc.source.eip.Block[]
function M.blocks(lines, from)
    local fence_at, table_at, skip = {}, {}, {}
    for _, f in ipairs(M.fences(lines)) do
        fence_at[f.first] = f
        for i = f.first, f.last do
            skip[i] = true
        end
    end
    for _, t in ipairs(M.tables(lines)) do
        table_at[t.first] = t
        for i = t.first, t.last do
            skip[i] = true
        end
    end
    local heading_at = {}
    for _, h in ipairs(M.headings(lines)) do
        heading_at[h.line] = h
    end
    local blocks = {}
    for i = from or 1, #lines do
        if fence_at[i] then
            local f = fence_at[i]
            local last = lines[f.last]:match("^%s*```") and f.last ~= f.first and f.last - 1 or f.last
            local code = {}
            for j = f.first + 1, last do
                table.insert(code, lines[j])
            end
            table.insert(blocks, { kind = "fence", line = i, lang = f.lang, code = code })
        elseif table_at[i] then
            local t = table_at[i]
            table.insert(blocks, { kind = "table", line = i, header = t.header, rows = t.rows })
        elseif heading_at[i] then
            local h = heading_at[i]
            table.insert(blocks, { kind = "heading", line = i, level = h.level, title = M.plain(h.title) })
        elseif not skip[i] then
            table.insert(blocks, { kind = "line", line = i, text = M.plain(lines[i]) })
        end
    end
    return number_lists(blocks)
end

return M

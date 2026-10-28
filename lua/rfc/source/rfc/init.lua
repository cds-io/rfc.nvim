-- Reads RFC text. `contents` reads the table of contents, with the line each
-- section's heading sits on; `references` reads the references section and
-- `cited_rfc` the RFC an entry cites; `mentions` finds the RFCs a line names;
-- `blocks` folds the text into the one list a renderer walks; `index` reads
-- the RFC Editor's index. Every function takes lines and answers tables, so
-- the specs run under plain busted and any plugin that reads RFCs can use
-- them.

---@class rfc.source.rfc
local M = {}

---@class rfc.source.rfc.Section
---@field number string     -- "3.1"; "A" for an appendix; "" for an unnumbered part (Index)
---@field label string      -- the number as the ToC row prints it: "3.1.", "Appendix A.", ""
---@field title string
---@field line integer      -- the heading's line in the text
---@field toc_line integer  -- the row's line in the table of contents

--- A row of the table of contents while it is being read; a Section once
--- its heading is found in the body.
---@class rfc.source.rfc.Row
---@field indent integer     -- the row's indent, which tells its level
---@field number string
---@field label string
---@field title string
---@field toc_line integer?  -- the row's line, set once the row is kept
---@field heading string?    -- the pattern its heading must start with, likewise

---@class rfc.source.rfc.Mention
---@field kind "rfc"|"section"|"citation"
---@field first integer     -- byte range of the text a link would replace
---@field last integer
---@field rfc string|nil    -- rfc: the number; section: the RFC the "of" names, when it names one
---@field number string|nil -- section: "3.1", without a trailing dot
---@field citation string|nil -- citation: "[CACHING]"; section: the citation the "of" names

---@class rfc.source.rfc.Block
---@field kind "header"|"heading"|"row"|"reference"|"line"
---@field line integer
---@field text string                 -- the line as written
---@field mentions rfc.source.rfc.Mention[]  -- what the line names; none for a page header
---@field section rfc.source.rfc.Section|nil -- heading, row: the section
---@field citation string|nil         -- reference: the key the entry defines

---@class rfc.source.rfc.IndexEntry
---@field number string
---@field label string        -- title, authors and date, as the index prints them
---@field obsoletes string|nil
---@field obsoleted_by string|nil
---@field formats string[]    -- "TXT", "HTML", "PDF", ...
---@field status string|nil   -- "PROPOSED STANDARD", as the index prints it

local refs = require("rfc.source.rfc.references")
M.contents = require("rfc.source.rfc.contents").contents
M.references, M.cited_rfc, M.mentions = refs.references, refs.cited_rfc, refs.mentions
M.index = require("rfc.source.rfc.index").index

--- Classifies the text into blocks, one per line, each carrying what it names:
--- a page header (left alone by a renderer), a section heading, a row of the
--- table of contents, the first line of a reference entry, or any other line. A
--- renderer walks this list.
---@param lines string[]
---@return rfc.source.rfc.Block[]
function M.blocks(lines)
    local sections = M.contents(lines)
    local heading_at, row_at = {}, {}
    for _, s in ipairs(sections) do
        heading_at[s.line] = s
        row_at[s.toc_line] = s
    end
    local citation_at = {}
    for citation, i in pairs(M.references(lines, sections).entries) do
        citation_at[i] = citation
    end
    local blocks = {}
    for i, line in ipairs(lines) do
        local block = { line = i, text = line, mentions = {} }
        if line:match("^RFC%s*%d+") then
            block.kind = "header"
        else
            block.mentions = M.mentions(line)
            if heading_at[i] then
                block.kind, block.section = "heading", heading_at[i]
            elseif row_at[i] then
                block.kind, block.section = "row", row_at[i]
            elseif citation_at[i] then
                block.kind, block.citation = "reference", citation_at[i]
            else
                block.kind = "line"
            end
        end
        table.insert(blocks, block)
    end
    return blocks
end

return M

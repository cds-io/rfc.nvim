-- Reads RFC text. `contents` reads the table of contents, with the line each
-- section's heading sits on; `references` reads the references section and
-- `cited_rfc` the RFC an entry cites; `mentions` finds the RFCs a line names;
-- `blocks` folds the text into the one list a renderer walks; `index` reads
-- the RFC Editor's index. Every function takes lines and answers tables, so
-- the specs run under plain busted and any plugin that reads RFCs can use
-- them.
local fp = require("cds.fp")

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

---@param s string
---@return string
local function trim(s)
    return (s:match("^%s*(.-)%s*$"))
end

---@param s string
---@return string
local function escape(s)
    return (s:gsub("%p", "%%%0"))
end

-- The ToC header: "Contents" or "Table of Contents", in any case, alone on its line.
---@param lines string[]
---@return integer|nil
local function header_line(lines)
    for i, line in ipairs(lines) do
        local t = trim(line):lower()
        if t == "contents" or t == "table of contents" then
            return i
        end
    end
end

-- A row's text after its label: the title, without dot leaders and a page number.
-- A page number is taken only after leaders or a gap, so a title that ends in a
-- number ("Changes from RFC 2818") keeps it.
---@param rest string
---@return string
local function row_title(rest)
    return rest:match("^(.-)%s*%.[%.%s]*%d+$") or rest:match("^(.-)%s%s+%d+$") or rest:match("^(.-)[%.%s]*$")
end

-- The shapes a numbered row takes. Each answers the row's indent, label and the
-- text after it; `number` reads the section number out of the label.
local ROWS = {
    {
        pattern = "^(%s*)([Aa][Pp][Pp][Ee][Nn][Dd][Ii][Xx]%s+%u[%.:]?)%s+(%S.*)$",
        number = function(label)
            return label:match("(%u)[%.:]?$")
        end,
    },
    {
        pattern = "^(%s*)(%d[%d%.]*)%s+(%S.*)$",
        number = function(label)
            return (label:gsub("%.$", ""))
        end,
    },
    {
        pattern = "^(%s*)(%u%.[%d%.]*)%s+(%S.*)$",
        number = function(label)
            return (label:gsub("%.$", ""))
        end,
    },
}

--- Reads a numbered row, by the first shape that fits.
---@param line string
---@return rfc.source.rfc.Row|nil
local function parse_numbered_row(line)
    return fp.find_map(ROWS, function(row)
        local indent, label, rest = line:match(row.pattern)
        if not indent then
            return nil
        end
        return { indent = #indent, number = row.number(label), label = label, title = row_title(rest) }
    end)
end

--- Reads an unnumbered part (Acknowledgements, Index): at the top-level indent,
--- starting with a capital. Anything deeper is a wrapped title's second line.
---@param line string
---@param top_indent integer|nil   -- the indent of the ToC's top-level rows, once known
---@return rfc.source.rfc.Row|nil
local function parse_unnumbered_row(line, top_indent)
    if not top_indent then
        return nil
    end
    local indent, rest = line:match("^(%s*)(%u.*)$")
    if not indent or #indent ~= top_indent then
        return nil
    end
    return { indent = #indent, number = "", label = "", title = row_title(rest) }
end

---@param line string
---@param top_indent integer|nil
---@return rfc.source.rfc.Row|nil
local function parse_row(line, top_indent)
    return parse_numbered_row(line) or parse_unnumbered_row(line, top_indent)
end

-- The pattern a heading line must start with, after trimming: the number with or
-- without its dot ("1.1  Purpose" and "1.1.  Purpose" both occur), then
-- separators; an unnumbered part is its title.
---@param section rfc.source.rfc.Row   -- or a Section: both carry number, label and title
---@return string
local function heading_prefix(section)
    if section.number == "" then
        return "^" .. escape(section.title)
    end
    local key = section.label:lower():match("^appendix") and ("[Aa][Pp][Pp][Ee][Nn][Dd][Ii][Xx]%s+" .. section.number)
        or escape(section.number)
    return "^" .. key .. "[%.:]?[%s%.:]+" .. escape(section.title)
end

-- Page furniture lands inside a table of contents when it crosses a page: a
-- "[Page n]" footer, and the running header, which is the same text on every
-- page. The headers are found by that repetition: any non-blank line that
-- occurs three times or more in the text.
---@param lines string[]
---@return fun(line: string): boolean
local function furniture(lines)
    local seen = {}
    for _, line in ipairs(lines) do
        if line:match("%S") then
            seen[line] = (seen[line] or 0) + 1
        end
    end
    return function(line)
        return (seen[line] or 0) >= 3 or line:match("%[Page%s+%w+%]%s*$") ~= nil
    end
end

---@param line string
---@return boolean
local function has_page(line)
    return line:match("%s%d+$") ~= nil or line:match("%.%d+$") ~= nil
end

--- Reads the table of contents, each row with the line its heading sits on in
--- the body; empty when the text has none. The ToC ends where the first section
--- begins: the first line that reads as the first row's heading and is not a
--- row itself (no page number, a different indent). A row whose heading never
--- appears is left out.
---@param lines string[]
---@return rfc.source.rfc.Section[]
function M.contents(lines)
    local header = header_line(lines)
    if not header then
        return {}
    end
    local rows, top_indent, stop, last_row_at = {}, nil, nil, nil
    local is_furniture = furniture(lines)
    for i = header + 1, #lines do
        local line = lines[i]
        if
            rows[1]
            and trim(line):match(rows[1].heading)
            and not has_page(line)
            and #line:match("^%s*") ~= rows[1].indent
        then
            stop = i
            break
        end
        -- a page break inside the ToC is neither a row nor a wrapped title
        local row = not is_furniture(line) and parse_row(line, top_indent) or nil
        if row then
            top_indent = top_indent and math.min(top_indent, row.indent) or row.indent
            row.toc_line = i
            row.heading = heading_prefix(row)
            table.insert(rows, row)
            last_row_at = i
        elseif
            not is_furniture(line)
            and last_row_at == i - 1
            and line:match("%S")
            and #line:match("^%s*") > rows[#rows].indent
        then
            local last = rows[#rows]
            last.title = last.title .. " " .. row_title(trim(line))
            last.heading = heading_prefix(last)
            last_row_at = i
        end
    end
    -- Headings come in ToC order, so each search starts where the last one
    -- ended; a row whose heading is missing costs one pass to the end.
    local sections, from = {}, stop
    for _, row in ipairs(rows) do
        for i = from or (row.toc_line + 1), #lines do
            if trim(lines[i]):match(row.heading) then
                table.insert(sections, {
                    number = row.number,
                    label = row.label,
                    title = row.title,
                    line = i,
                    toc_line = row.toc_line,
                })
                from = i + 1
                break
            end
        end
    end
    return sections
end

local CITATION = "%[[%w/%.%-]+%]"

--- Reads the references section: its heading line and every entry's citation
--- key with the line it starts on. `line` is nil when no section is titled
--- References, and the entries are then empty.
---@param lines string[]
---@param sections rfc.source.rfc.Section[]
---@return { line: integer|nil, entries: table<string, integer> }
function M.references(lines, sections)
    local from = fp.find_map(sections, function(s)
        return s.title == "References" and s.line or nil
    end)
    local entries = {}
    if from then
        for i = from, #lines do
            local citation = lines[i]:match("^%s*(" .. CITATION .. ")")
            if citation and not entries[citation] then
                entries[citation] = i
            end
        end
    end
    return { line = from, entries = entries }
end

--- Finds the RFC a reference entry cites: the first "RFC nnnn" in the entry's
--- block, which runs to the next blank line.
---@param lines string[]
---@param entry_line integer
---@return string|nil
function M.cited_rfc(lines, entry_line)
    for i = entry_line, #lines do
        if not lines[i]:match("%S") then
            return nil
        end
        local number = lines[i]:match("RFC%s*(%d+)")
        if number then
            return number
        end
    end
end

--- Finds every reference a line makes, in order of position: "[RFC2616]" and
--- "RFC 2616" as rfc mentions, "Section 3.1" as a section (with the RFC or
--- citation an "of" names), and "[CACHING]" as a citation. Each scan is a
--- gmatch with position captures; the bracketed mentions are blanked out of the
--- line the bare scan reads, so "RFC2616" inside "[RFC2616]" is found once.
---@param line string
---@return rfc.source.rfc.Mention[]
function M.mentions(line)
    local found = {}
    local function add(m)
        table.insert(found, m)
    end
    for first, number, after in line:gmatch("()%[RFC(%d+)%]()") do
        add({ kind = "rfc", first = first, last = after - 1, rfc = number })
    end
    local bare = line:gsub("%[RFC%d+%]", function(m)
        return (" "):rep(#m)
    end)
    for first, number, after in bare:gmatch("()RFC%s*(%d+)()") do
        if not bare:sub(first - 1, first - 1):match("%w") then
            add({ kind = "rfc", first = first, last = after - 1, rfc = number })
        end
    end
    for first, citation, after in line:gmatch("()(" .. CITATION .. ")()") do
        if not citation:match("^%[RFC%d+%]$") then
            add({ kind = "citation", first = first, last = after - 1, citation = citation })
        end
    end
    for first, number, after in line:gmatch("[Ss]ection%s+()(%d[%d%.]*)()") do
        local last = after - 1
        if number:match("%.$") then
            number, last = number:sub(1, -2), last - 1
        end
        local rest = line:sub(last + 1)
        local m = { kind = "section", first = first, last = last, number = number }
        m.rfc = rest:match("^%.?%s+of%s+%[?RFC%s*(%d+)%]?")
        if not m.rfc then
            m.citation = rest:match("^%.?%s+of%s+(" .. CITATION .. ")")
        end
        add(m)
    end
    table.sort(found, function(a, b)
        return a.first < b.first
    end)
    return found
end

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

--- Reads the RFC Editor's index (rfc-index.txt) as entries. A block is a number
--- at column 0 and the indented lines that follow it; "Not Issued" numbers are
--- left out.
---@param lines string[]
---@return rfc.source.rfc.IndexEntry[]
function M.index(lines)
    local entries = {}
    local block
    local function close()
        if not block then
            return
        end
        local number, text = block.number, block.text
        block = nil
        if text:match("^Not Issued") then
            return
        end
        local formats = {}
        for format in (text:match("%(Format:%s*(.-)%)") or ""):gmatch("[^,%s]+") do
            table.insert(formats, format)
        end
        table.insert(entries, {
            number = number,
            label = text:match("^(.-%u%l+ %d%d%d%d%.)") or (text:match("^(.-)%s*%(") or text),
            obsoletes = text:match("%(Obsoletes%s+(.-)%)"),
            obsoleted_by = text:match("%(Obsoleted by%s+(.-)%)"),
            formats = formats,
            status = text:match("%(Status:%s*(.-)%)"),
        })
    end
    for _, line in ipairs(lines) do
        local number, text = line:match("^(%d+)%s+(%S.*)$")
        if number then
            close()
            block = { number = number, text = trim(text) }
        elseif block and line:match("^%s+%S") then
            block.text = block.text .. " " .. trim(line)
        elseif block then
            close()
        end
    end
    close()
    return entries
end

return M

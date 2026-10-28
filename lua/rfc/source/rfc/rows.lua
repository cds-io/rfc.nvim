-- RFC contents row grammar.
local fp = require("cds.fp")
local M = {}

---@param s string
---@return string
local function escape(s)
    return (s:gsub("%p", "%%%0"))
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

M.parse, M.title, M.heading = parse_row, row_title, heading_prefix

return M

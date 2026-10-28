local fp = require("cds.fp")
-- RFC citations and reference entries.
local M = {}

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

return M

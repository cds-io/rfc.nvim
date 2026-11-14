-- MediaWiki inline text and entities.
local M = {}

---@param s string
---@return string
local function trim(s)
    return (s:match("^%s*(.-)%s*$"))
end

---@param code integer
---@return string
local function utf8_char(code)
    if code < 0x80 then
        return string.char(code)
    elseif code < 0x800 then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
    elseif code < 0x10000 then
        return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
    end
    return string.char(
        0xF0 + math.floor(code / 0x40000),
        0x80 + math.floor(code / 0x1000) % 0x40,
        0x80 + math.floor(code / 0x40) % 0x40,
        0x80 + code % 0x40
    )
end

-- stylua: ignore
local ENTITIES = {
  amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " ",
  rarr = "→", larr = "←", le = "≤", ge = "≥", ne = "≠", times = "×", minus = "−",
  mdash = "—", ndash = "–", hellip = "…",
}

---@param s string
---@return string
local function unescape(s)
    return (
        s:gsub("&(#?%w+);", function(e)
            if ENTITIES[e] then
                return ENTITIES[e]
            end
            local n = e:match("^#(%d+)$")
            if n then
                return utf8_char(assert(tonumber(n)))
            end
            local hex = e:match("^#[xX](%x+)$")
            if hex then
                return utf8_char(assert(tonumber(hex, 16)))
            end
            return "&" .. e .. ";"
        end)
    )
end
--- Replaces every wiki link with its text: [[x|text]] becomes text, [[x]]
--- becomes x, and a file link becomes nothing.
---@param s string
---@return string
function M.unlink(s)
    return (
        s:gsub("%[%[([^%]]-)%]%]", function(inner)
            if inner:match("^File:") then
                return ""
            end
            return inner:match("^.*|(.-)$") or inner
        end)
    )
end

--- Turns MediaWiki inline markup into plain text: bold and italic marks are
--- dropped; <code>, <tt> and an inline <pre> become backticks; every other tag
--- is dropped with its text kept; an external link becomes its text and
--- address; a wiki link to a proposal (or into the document) is kept for the
--- mention pass and any other is unwrapped; entities are unescaped.
---@param s string
---@return string
function M.plain(s)
    local spans = {}
    local function keep(span)
        table.insert(spans, span)
        return "\1" .. #spans .. "\1"
    end
    s = s:gsub("`[^`]*`", keep)
    s = s:gsub("<code>(.-)</code>", function(x)
        return keep("`" .. x .. "`")
    end)
    s = s:gsub("<tt>(.-)</tt>", function(x)
        return keep("`" .. x .. "`")
    end)
    s = s:gsub("<pre>(.-)</pre>", function(x)
        return keep("`" .. x .. "`")
    end)
    s = s:gsub("%[%[([^%]]-)%]%]", function(inner)
        if inner:match("^bip%-%d+%.%a+") or inner:match("^#") then
            return "[[" .. inner .. "]]"
        end
        return M.unlink("[[" .. inner .. "]]")
    end)
    s = s:gsub("%[(https?://[^%s%]]+)%s+([^%]]+)%]", "%2 (%1)")
    s = s:gsub("%[(https?://[^%s%]]+)%]", "%1")
    s = s:gsub("'''", ""):gsub("''", "")
    s = s:gsub("</?%a[%w%-]*%s[^>]*>", ""):gsub("</?%a[%w%-]*/?>", "")
    s = unescape(s)
    return (s:gsub("\1(%d+)\1", function(n)
        return spans[tonumber(n)]
    end))
end

--- Reads a row's cell: an attribute prefix (colspan=4|) is dropped, and the
--- text comes back plain and unlinked.
---@param cell string
---@return string
local function plain_cell(cell)
    local text = cell:match("^[^|]*=[^|]*|(.*)$") or cell
    return trim(M.unlink(M.plain(text)))
end

M.cell = plain_cell

return M

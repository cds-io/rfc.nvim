-- MediaWiki code and headings.
local inline = require("rfc.source.bip.inline")
local M = {}

--- Finds the code blocks, <pre> and <source lang="x">. A line that starts with
--- the opening tag opens one, and the text after the tag is its first line; the
--- line holding the closing tag ends it, and the text before the tag is its
--- last; both tags on one line make a one-line block. A tag inside other text
--- on its line is a code span, so no block. An unterminated block runs to the
--- end.
---@param lines string[]
---@return rfc.source.bip.Code[]
function M.code(lines)
    local blocks = {}
    local i = 1
    while i <= #lines do
        local line = lines[i]
        local lang, rest = line:match('^%s*<source%s+lang="([^"]*)"%s*>(.*)$')
        local closer = lang and "</source>" or nil
        if not lang then
            rest = line:match("^%s*<pre>(.*)$")
            if rest then
                lang, closer = "", "</pre>"
            end
        end
        if closer then
            local code = {}
            local function open_line(text)
                if text ~= "" then
                    table.insert(code, text)
                end
            end
            local before = rest:match("^(.-)" .. closer)
            if before then
                open_line(before)
                table.insert(blocks, { first = i, last = i, lang = lang, code = code })
                i = i + 1
            else
                open_line(rest)
                local last = i + 1
                while last <= #lines and not lines[last]:find(closer, 1, true) do
                    table.insert(code, lines[last])
                    last = last + 1
                end
                if last <= #lines then
                    open_line(lines[last]:match("^(.-)" .. closer))
                else
                    last = #lines
                end
                table.insert(blocks, { first = i, last = last, lang = lang, code = code })
                i = last + 1
            end
        else
            i = i + 1
        end
    end
    return blocks
end

---@param blocks { first: integer, last: integer }[]
---@return fun(i: integer): boolean
local function within(blocks)
    return function(i)
        for _, b in ipairs(blocks) do
            if i >= b.first and i <= b.last then
                return true
            end
        end
        return false
    end
end

--- Finds the headings outside code: ==Title== is level 1, each further sign one
--- deeper; the titles come back plain.
---@param lines string[]
---@return rfc.source.bip.Heading[]
function M.headings(lines)
    local headings, inside = {}, within(M.code(lines))
    for i, line in ipairs(lines) do
        local signs, title = line:match("^(=+)%s*(.-)%s*=+%s*$")
        if signs and title ~= "" and not inside(i) then
            table.insert(headings, { level = math.max(#signs - 1, 1), title = inline.plain(title), line = i })
        end
    end
    return headings
end

return M

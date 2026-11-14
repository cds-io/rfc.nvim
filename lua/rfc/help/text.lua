-- Help text cleanup, title, line formatting and wrapping.
local WIDTH = 78
local M = {}

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

--- The text wrapped at spaces within the width, each line under the
--- indent; a word longer than the room (a |tag|) stands alone on a line;
--- a newline in the text is a hard break.
---@param text string
---@param indent string
---@param width? integer
---@return string[]
function M.wrap(text, indent, width)
    width = width or WIDTH
    local out = {}
    for piece in (text .. "\n"):gmatch("(.-)\n") do
        local line = nil
        for word in piece:gmatch("%S+") do
            if not line then
                line = indent .. word
            elseif #line + 1 + #word <= width then
                line = line .. " " .. word
            else
                table.insert(out, line)
                line = indent .. word
            end
        end
        table.insert(out, line or indent:gsub("%s+$", ""))
    end
    return out
end

return M

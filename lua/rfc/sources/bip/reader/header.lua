-- Proposal format and preamble.
local trim = function(s)
    return (s:match("^%s*(.-)%s*$"))
end
local M = {}

--- Says which markup the text is written in: MediaWiki when a line is a ==
--- heading (every such proposal has one), markdown otherwise.
---@param lines string[]
---@return "mediawiki"|"markdown"
function M.format(lines)
    for _, line in ipairs(lines) do
        if line:match("^==+[^=]") then
            return "mediawiki"
        end
    end
    return "markdown"
end

-- a key starts with a letter; a continued value may start with a date
local FIELD = "^%s+(%a[%w%-]*):%s*(.-)%s*$"

--- Reads the preamble, the first <pre> block (a ``` fence in markdown) whose
--- lines are `  Key: value`, into a table keyed by the lowercased keys, and
--- answers the lines it spans. A value continued on deeper-indented lines is
--- joined with spaces. Without one the table is empty and the range nil.
---@param lines string[]
---@return table<string, string> fields
---@return integer|nil first
---@return integer|nil last
function M.preamble(lines)
    local i = 1
    while i <= #lines do
        local opener = lines[i]:match("^%s*<pre>%s*$") and "</pre>" or lines[i]:match("^%s*```%s*$") and "```" or nil
        if opener then
            local last = i + 1
            while last <= #lines and not lines[last]:find(opener, 1, true) do
                last = last + 1
            end
            if lines[i + 1] and lines[i + 1]:match(FIELD) then
                local fields, key = {}, nil
                for j = i + 1, math.min(last, #lines) - 1 do
                    local k, v = lines[j]:match(FIELD)
                    if k then
                        key, fields[k:lower()] = k:lower(), v
                    elseif key and lines[j]:match("^%s+%S") then
                        fields[key] = fields[key] .. " " .. trim(lines[j])
                    end
                end
                return fields, i, math.min(last, #lines)
            end
            i = last + 1
        else
            i = i + 1
        end
    end
    return {}, nil, nil
end

return M

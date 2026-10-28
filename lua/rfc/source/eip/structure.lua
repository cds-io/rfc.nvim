-- Markdown frontmatter, fences and headings.
local M = {}

---@param s string
---@return string
local function trim(s)
    return (s:match("^%s*(.-)%s*$"))
end

--- Reads the YAML frontmatter into a table of strings and answers the first
--- line of the body. A value on the lines that follow its key (indented) is
--- joined to it. Without a frontmatter the table is empty and the body starts
--- at 1.
---@param lines string[]
---@return table<string, string> fields
---@return integer body
function M.frontmatter(lines)
    if lines[1] ~= "---" then
        return {}, 1
    end
    local fields, key = {}, nil
    for i = 2, #lines do
        local line = lines[i]
        if line == "---" then
            return fields, i + 1
        end
        local k, v = line:match("^([%w%-]+):%s*(.-)%s*$")
        if k then
            key, fields[k] = k, v
        elseif key and line:match("^%s+%S") then
            fields[key] = (fields[key] == "" and "" or fields[key] .. " ") .. trim(line)
        end
    end
    return fields, #lines + 1
end

--- Finds the fenced code blocks, so a # inside one is not read as a heading.
---@param lines string[]
---@return rfc.source.eip.Fence[]
function M.fences(lines)
    local fences, open = {}, nil
    for i, line in ipairs(lines) do
        local lang = line:match("^%s*```%s*(.-)%s*$")
        if lang then
            if open then
                open.last = i
                table.insert(fences, open)
                open = nil
            else
                open = { first = i, lang = lang }
            end
        end
    end
    if open then
        open.last = #lines
        table.insert(fences, open)
    end
    return fences
end

---@param fences rfc.source.eip.Fence[]
---@return fun(i: integer): boolean
local function fenced(fences)
    return function(i)
        for _, f in ipairs(fences) do
            if i >= f.first and i <= f.last then
                return true
            end
        end
        return false
    end
end

--- Finds the headings of the body, outside fenced code.
---@param lines string[]
---@return rfc.source.eip.Heading[]
function M.headings(lines)
    local headings, inside = {}, fenced(M.fences(lines))
    for i, line in ipairs(lines) do
        local hashes, title = line:match("^(#+)%s+(.-)%s*#*%s*$")
        if hashes and not inside(i) then
            table.insert(headings, { level = #hashes, title = title, line = i })
        end
    end
    return headings
end

return M

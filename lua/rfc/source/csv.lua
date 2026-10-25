-- Reads CSV files whose records are one physical line each. `fields` splits
-- one line with RFC 4180 quoting: a quoted field may hold commas, and a quote
-- inside it is written twice. `records` reads a whole file, naming each field
-- after the header line. A field spanning lines is out of scope.
---@class rfc.source.csv
local M = {}

--- Splits one line into its fields. An unterminated quote is refused.
---@param line string
---@return string[]|nil
---@return string|nil err
function M.fields(line)
    local fields, field, in_quotes, i = {}, {}, false, 1
    while i <= #line do
        local c = line:sub(i, i)
        if in_quotes then
            if c == '"' then
                if line:sub(i + 1, i + 1) == '"' then
                    table.insert(field, '"')
                    i = i + 1
                else
                    in_quotes = false
                end
            else
                table.insert(field, c)
            end
        elseif c == '"' then
            in_quotes = true
        elseif c == "," then
            table.insert(fields, table.concat(field))
            field = {}
        else
            table.insert(field, c)
        end
        i = i + 1
    end
    if in_quotes then
        return nil, "unterminated quote"
    end
    table.insert(fields, table.concat(field))
    return fields
end

--- Reads the lines after the header as records keyed by its names; a blank line
--- is skipped, and a line with a different number of fields is refused.
---@param lines string[]
---@return table<string, string>[]|nil
---@return string|nil err
function M.records(lines)
    local header, err = M.fields(lines[1] or "")
    if not header then
        return nil, err
    end
    local records = {}
    for i = 2, #lines do
        if lines[i] ~= "" then
            local fields, ferr = M.fields(lines[i])
            if not fields then
                return nil, ferr
            end
            if #fields ~= #header then
                return nil, ("line %d: %d fields, header has %d"):format(i, #fields, #header)
            end
            local record = {}
            for j, name in ipairs(header) do
                record[name] = fields[j]
            end
            table.insert(records, record)
        end
    end
    return records
end

return M

-- Proposal fields and resolved inline parts.
local help = require("rfc.help.tags")
local M = {}

---@param key string
---@return string
local function label(key)
    return key:sub(1, 1):upper() .. key:sub(2)
end

---@class rfc.InlinePart
---@field text string
---@field target? string -- application tag, without help or Markdown delimiters

---@alias rfc.Inline rfc.InlinePart[]

--- Render resolved text/link parts without interpreting literal text as markup.
--- Plain text is transformed as one string, keeping inline code spans intact.
---@param parts rfc.Inline
---@param link fun(target: string): string
---@param plain? fun(text: string): string
---@return string
function M.format(parts, link, plain)
    local out = {}
    for i, part in ipairs(parts) do
        out[i] = part.target and ("\1" .. i .. "\2") or part.text
    end
    local text = table.concat(out)
    text = plain and plain(text) or text
    return (text:gsub("\1(%d+)\2", function(index)
        return link(parts[tonumber(index)].target)
    end))
end

---@param target string
---@return string
local function help_link(target)
    return "|" .. target .. "|"
end

--- The tag a source mention names, resolved once while preparing the model.
---@param spec rfc.ProposalSpec
---@param id string
---@param mention rfc.source.Mention
---@return string
local function target(spec, id, mention)
    local tag = (mention.kind or spec.prefix) .. (mention.id or id)
    return mention.section and (tag .. "-" .. help.slug(mention.section)) or tag
end

--- Literal text and resolved links, in source order.
---@param spec rfc.ProposalSpec
---@param id string
---@param text string
---@return rfc.Inline
function M.inline(spec, id, text)
    local out, from = {}, 1
    for _, mention in ipairs(spec.mentions(text)) do
        if mention.first > from then
            out[#out + 1] = { text = text:sub(from, mention.first - 1) }
        end
        out[#out + 1] = { text = text:sub(mention.first, mention.last), target = target(spec, id, mention) }
        from = mention.last + 1
    end
    if from <= #text then
        out[#out + 1] = { text = text:sub(from) }
    end
    return out
end

---@param prefix string
---@param value string
---@return rfc.Inline
local function number_links(prefix, value)
    local out = {}
    for n in value:gmatch("%d+") do
        if #out > 0 then
            out[#out + 1] = { text = ", " }
        end
        local tag = prefix .. n:gsub("^0+(%d)", "%1")
        out[#out + 1] = { text = tag, target = tag }
    end
    return out
end

--- Compatibility export of a numeric field as help links.
---@param prefix string
---@param value string
---@return string?
function M.links(prefix, value)
    local parts = number_links(prefix, value)
    return #parts > 0 and M.format(parts, help_link) or nil
end

---@param prefix string
---@param fields table<string, string>
---@param row rfc.ProposalRow
---@return rfc.Inline?
local function row_parts(prefix, fields, row)
    local value = fields[row.key]
    if not value or value == "" then
        return nil
    end
    local parts
    if row.as == "links" then
        parts = number_links(prefix, value)
    elseif type(row.as) == "function" then
        local items = row.as(value)
        parts = #items > 0 and { { text = table.concat(items, ", ") } } or {}
    else
        parts = { { text = value } }
    end
    if #parts == 0 then
        return nil
    end
    table.insert(parts, 1, { text = label(row.key) .. ": " })
    return parts
end

--- Compatibility export of a header row as help text.
---@param prefix string
---@param fields table<string, string>
---@param row rfc.ProposalRow
---@return string?
function M.row(prefix, fields, row)
    local parts = row_parts(prefix, fields, row)
    return parts and M.format(parts, help_link) or nil
end

--- Compatibility helper; shared model consumers use pre-resolved inline parts.
---@param spec rfc.ProposalSpec
---@param id string
---@return fun(line: string): string
function M.linker(spec, id)
    return function(line)
        return M.format(M.inline(spec, id, line), help_link)
    end
end

M.row_parts, M.label, M.help_link = row_parts, label, help_link

return M

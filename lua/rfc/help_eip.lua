-- An Ethereum proposal as a Vim help document. render is total: the
-- frontmatter becomes a header block, the headings get tags and a table of
-- contents of links, fenced code becomes help code blocks, and every EIP or
-- ERC the text names becomes a link. Nothing here touches the editor.
local eip = require("cds.eip")
local help = require("rfc.help")

local M = {}

---@param line string
---@return string
local function link(line)
    local mentions = eip.mentions(line)
    for i = #mentions, 1, -1 do
        local m = mentions[i]
        line = line:sub(1, m.first - 1) .. "|" .. m.kind .. m.id .. "|" .. line:sub(m.last + 1)
    end
    return line
end

--- The document for a proposal's text.
---@param prefix "eip"|"erc"
---@param id string
---@param lines string[]
---@return rfc.HelpDoc
function M.render(prefix, id, lines)
    local fields, body = eip.frontmatter(lines)
    local label = prefix:upper()
    local file_tag = prefix .. id
    local out, tags = {}, {}
    local function put(line)
        table.insert(out, line)
    end
    local function tag(name)
        table.insert(tags, { name = name, line = #out })
    end

    put(help.with_tag("*" .. file_tag .. ".txt*  " .. (fields.title or (label .. " " .. id)), file_tag))
    tag(file_tag)
    tag(file_tag .. ".txt")
    if prefix == "erc" then
        -- an ERC keeps its EIP number, and the text of other proposals uses both
        out[1] = out[1] .. " *eip" .. id .. "*"
        tag("eip" .. id)
    end
    local header = { label .. "-" .. id }
    for _, key in ipairs({ "status", "type", "category", "created" }) do
        if fields[key] then
            table.insert(header, key:sub(1, 1):upper() .. key:sub(2) .. ": " .. fields[key])
        end
    end
    put(table.concat(header, "  "))
    local requires = eip.requires(fields)
    if #requires > 0 then
        local links = {}
        for _, r in ipairs(requires) do
            table.insert(links, "|eip" .. r .. "|")
        end
        put("Requires: " .. table.concat(links, ", "))
    end
    if fields.author then
        put("Author: " .. fields.author)
    end
    if fields.status == "Moved" then
        put("Moved: see |erc" .. id .. "|")
    end
    put("")

    local headings = {}
    for _, h in ipairs(eip.headings(lines)) do
        if h.line >= body then
            table.insert(headings, h)
        end
    end
    local tag_at, used = {}, {}
    for _, h in ipairs(headings) do
        local name = file_tag .. "-" .. help.slug(h.title)
        if used[name] then
            used[name] = used[name] + 1
            name = name .. "-" .. used[name]
        else
            used[name] = 1
        end
        tag_at[h.line] = { name = name, heading = h }
    end
    if #headings > 0 then
        put("CONTENTS")
        for _, h in ipairs(headings) do
            put(string.rep("  ", math.max(h.level - 1, 1)) .. "|" .. tag_at[h.line].name .. "|  " .. h.title)
        end
        put("")
    end

    local opens, closes, inside = {}, {}, {}
    for _, f in ipairs(eip.fences(lines)) do
        opens[f.first] = f.lang
        if lines[f.last]:match("^%s*```") and f.last ~= f.first then
            closes[f.last] = true
        end
        for i = f.first + 1, f.last do
            inside[i] = true
        end
    end
    for i = body, #lines do
        local line = lines[i]
        if tag_at[i] then
            local h = tag_at[i].heading
            put(help.with_tag(h.level <= 2 and h.title:upper() or h.title, tag_at[i].name))
            tag(tag_at[i].name)
        elseif opens[i] then
            put(">" .. opens[i])
        elseif closes[i] then
            put("<")
        elseif inside[i] then
            put("    " .. line)
        else
            put(link(line))
        end
    end
    if inside[#lines] and not closes[#lines] then
        put("<")
    end
    put("")
    put(help.MODELINE)
    return { lines = out, tags = tags }
end

return M

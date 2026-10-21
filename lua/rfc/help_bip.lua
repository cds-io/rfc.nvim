-- A Bitcoin proposal as a Vim help document. render is total: the preamble
-- becomes a header block, the headings get tags and a table of contents of
-- links, code becomes help code blocks, tables become aligned columns, the
-- footnotes a numbered list, inline markup becomes its text, and every
-- proposal the text names becomes a link, to its section when it names
-- one. A proposal written in markdown reads its body through cds.eip. The
-- body fold is the one in rfc.proposal. Nothing here touches the editor.
local bip = require("cds.bip")
local eip = require("cds.eip")
local help = require("rfc.help")
local proposal = require("rfc.proposal")

local M = {}

--- The link pass for the proposal `id`: a mention becomes |bipN|, or
--- |bipN-section| when it names a section, the document's own number
--- standing in for a link into itself.
---@param id string
---@return fun(line: string): string
local function linker(id)
    return function(line)
        local mentions = bip.mentions(line)
        for i = #mentions, 1, -1 do
            local m = mentions[i]
            local tag = "bip" .. (m.id or id)
            if m.section then
                tag = tag .. "-" .. help.slug(m.section)
            end
            line = line:sub(1, m.first - 1) .. "|" .. tag .. "|" .. line:sub(m.last + 1)
        end
        return line
    end
end

--- The numbers a field names, as links.
---@param field string|nil
---@return string|nil
local function links(field)
    local out = {}
    for n in (field or ""):gmatch("%d+") do
        table.insert(out, "|bip" .. n:gsub("^0+(%d)", "%1") .. "|")
    end
    return #out > 0 and table.concat(out, ", ") or nil
end

--- The document for a proposal's text.
---@param id string
---@param lines string[]
---@return rfc.HelpDoc
function M.render(id, lines)
    local fields, first, last = bip.preamble(lines)
    local file_tag = "bip" .. id
    local out, tags = {}, {}
    local function put(line)
        table.insert(out, line)
    end
    local function tag(name)
        table.insert(tags, { name = name, line = #out })
    end

    put(help.with_tag("*" .. file_tag .. ".txt*  " .. (fields.title or ("BIP " .. id)), file_tag))
    tag(file_tag)
    tag(file_tag .. ".txt")
    local header = { "BIP-" .. id }
    for _, key in ipairs({ "layer", "status", "type", "assigned" }) do
        if fields[key] then
            table.insert(header, key:sub(1, 1):upper() .. key:sub(2) .. ": " .. fields[key])
        end
    end
    put(table.concat(header, "  "))
    for _, key in ipairs({ "requires", "replaces" }) do
        local named = links(fields[key])
        if named then
            put(key:sub(1, 1):upper() .. key:sub(2) .. ": " .. named)
        end
    end
    if fields.authors then
        put("Authors: " .. fields.authors)
    end
    put("")

    local blocks
    if bip.format(lines) == "markdown" then
        blocks = eip.blocks(lines, last and last + 1 or 1)
    else
        blocks = bip.blocks(lines, first and { first = first, last = last } or nil)
    end
    local body, body_tags = proposal.body(blocks, file_tag, linker(id))
    local offset = #out
    for _, line in ipairs(body) do
        put(line)
    end
    for _, t in ipairs(body_tags) do
        table.insert(tags, { name = t.name, line = offset + t.line })
    end
    put("")
    put(help.MODELINE)
    put(help.FOOTER)
    return { lines = out, tags = tags }
end

return M

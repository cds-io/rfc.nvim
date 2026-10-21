-- An Ethereum proposal as a Vim help document. render is total: the
-- frontmatter becomes a header block, the headings get tags and a table of
-- contents of links, fenced code becomes help code blocks, tables become
-- aligned columns, inline HTML and emphasis become their text, and every
-- EIP or ERC the text names becomes a link; the body fold is the one in
-- rfc.proposal. Nothing here touches the editor.
local eip = require("cds.eip")
local help = require("rfc.help")
local proposal = require("rfc.proposal")

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

--- The document for a proposal's text. Every proposal is tagged by its EIP
--- number; one in the ERC category also carries its ERC name, since the
--- texts of other proposals use both.
---@param id string
---@param lines string[]
---@return rfc.HelpDoc
function M.render(id, lines)
    local fields, body_at = eip.frontmatter(lines)
    local label = fields.category == "ERC" and "ERC" or "EIP"
    local file_tag = "eip" .. id
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
    if fields.category == "ERC" then
        out[1] = out[1] .. " *erc" .. id .. "*"
        tag("erc" .. id)
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

    -- the body as blocks whose text is already plain; the fold over them is
    -- the one every proposal render shares
    local body, body_tags = proposal.body(eip.blocks(lines, body_at), file_tag, link)
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

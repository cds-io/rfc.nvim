-- A Solana improvement document as a Vim help document. render is total:
-- the frontmatter becomes a header block (the relations to other
-- proposals as links, the authors as one line), the headings get tags and
-- a table of contents of links, fenced code becomes help code blocks,
-- tables become aligned columns, and every proposal the text names
-- becomes a link, to its section when it names one. The body is read by
-- cds.eip; the body fold is the one in rfc.proposal. Nothing here touches
-- the editor.
local eip = require("cds.eip")
local simd = require("cds.simd")
local help = require("rfc.help")
local proposal = require("rfc.proposal")

local M = {}

---@param line string
---@return string
local function link(line)
    local mentions = simd.mentions(line)
    for i = #mentions, 1, -1 do
        local m = mentions[i]
        local tag = "simd" .. m.id
        if m.section then
            tag = tag .. "-" .. help.slug(m.section)
        end
        line = line:sub(1, m.first - 1) .. "|" .. tag .. "|" .. line:sub(m.last + 1)
    end
    return line
end

--- The proposals a relation field names, as links; nil when none.
---@param value string|nil
---@return string|nil
local function links(value)
    local out = {}
    for n in (value or ""):gmatch("%d+") do
        table.insert(out, "|simd" .. n:gsub("^0+(%d)", "%1") .. "|")
    end
    return #out > 0 and table.concat(out, ", ") or nil
end

---@param key string
---@return string
local function label(key)
    return key:sub(1, 1):upper() .. key:sub(2)
end

--- The document for a proposal's text.
---@param id string
---@param lines string[]
---@return rfc.HelpDoc
function M.render(id, lines)
    local fields, body_at = eip.frontmatter(lines)
    local file_tag = "simd" .. id
    local out, tags = {}, {}
    local function put(line)
        table.insert(out, line)
    end
    local function tag(name)
        table.insert(tags, { name = name, line = #out })
    end

    put(help.with_tag("*" .. file_tag .. ".txt*  " .. (fields.title or ("SIMD " .. id)), file_tag))
    tag(file_tag)
    tag(file_tag .. ".txt")
    local header = { ("SIMD-%04d"):format(tonumber(simd.number(fields.simd) or id)) }
    for _, key in ipairs({ "category", "type", "status", "created" }) do
        if fields[key] and fields[key] ~= "" then
            table.insert(header, label(key) .. ": " .. fields[key])
        end
    end
    put(table.concat(header, "  "))
    if fields.feature and fields.feature ~= "" then
        put("Feature: " .. fields.feature)
    end
    for _, key in ipairs({ "supersedes", "superseded-by", "extends" }) do
        local named = links(fields[key])
        if named then
            put(label(key) .. ": " .. named)
        end
    end
    local authors = simd.list(fields.authors)
    if #authors > 0 then
        put("Authors: " .. table.concat(authors, ", "))
    end
    put("")

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

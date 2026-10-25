-- Reads Solana improvement documents. The body is markdown behind a YAML
-- frontmatter, which rfc.source.eip.frontmatter reads into one string per field,
-- joining a list onto one line; `list` and `number` then read those strings.
-- SIMD-0064 opens with
--
--   simd: '0064'
--   title: Transaction Receipts
--   authors:
--     - Anoushk Kharangate (Tinydancer)
--     - Richard Patel (Jump)
--
-- and the fields come back as `simd = "'0064'"` and
-- `authors = "- Anoushk Kharangate (Tinydancer) - Richard Patel (Jump)"`;
-- `number(fields.simd)` is "64", and `list(fields.authors)` is
-- { "Anoushk Kharangate (Tinydancer)", "Richard Patel (Jump)" }. A list
-- written inline ("A (Anza), B (Anza)") splits at its commas.
--
-- `mentions` finds the proposals a line names, as a link to a proposal's file
-- or a bare SIMD-0033, and `index` reads the proposals directory as the
-- GitHub contents API lists it: every "NNNN-slug.md" name becomes an entry,
-- its title read from the slug. Every function takes strings and answers
-- tables, so the specs run under plain busted.
local mentions = require("rfc.source.mentions")

---@class rfc.source.simd
local M = {}

---@class rfc.source.simd.Mention
---@field kind "simd"
---@field id string          -- the number without leading zeros
---@field section string|nil -- the anchor a link names, when it names one
---@field first integer      -- byte range of the text a link would replace
---@field last integer

---@class rfc.source.simd.Entry
---@field id string
---@field file string   -- 0064-transaction-receipt.md
---@field title string  -- the file's slug as words: Transaction Receipt

---@param id string
---@return string
local function number(id)
    return (id:gsub("^0+(%d)", "%1"))
end

---@param id string
---@param section string|nil
---@return table
local function named(id, section)
    return { kind = "simd", id = number(id), section = section }
end

--- Finds every proposal a line names, in order of position: a markdown link to
--- a proposal's file (`./0033-slug.md`, or the repository's address for it,
--- with an anchor after #), the whole link; and a bare SIMD-0033, SIMD-33, SIMD
--- 0033 or SIMD 33 outside those. Numbers lose their leading zeros.
---@param line string
---@return rfc.source.simd.Mention[]
function M.mentions(line)
    return mentions.scan(
        line,
        { { "%[[^%]]*%]%([^%)%s]-(%d%d%d%d)%-[%w%-%._]-%.md#?([%w%-_]*)%)", named } },
        { "SIMD[%- ]?0*(%d+)", named }
    )
end

--- Reads the proposals directory as entries: every `"name": "NNNN-slug.md"` in
--- the contents API's answer, the title read from the slug (a few slugs join
--- their words with underscores).
---@param lines string[]
---@return rfc.source.simd.Entry[]
function M.index(lines)
    local entries = {}
    for _, line in ipairs(lines) do
        for id, slug in line:gmatch('"name"%s*:%s*"(%d%d%d%d)%-([%w%-%._]-)%.md"') do
            local title = slug:gsub("[%-_]", " "):gsub("(%a)([%w]*)", function(first, rest)
                return first:upper() .. rest
            end)
            table.insert(entries, { id = number(id), file = id .. "-" .. slug .. ".md", title = title })
        end
    end
    return entries
end

--- Splits a frontmatter list as rfc.source.eip.frontmatter joins it ("- A - B"), or an
--- inline value at its commas; an empty or missing value gives none.
---@param value string|nil
---@return string[]
function M.list(value)
    local items = {}
    if not value or value == "" then
        return items
    end
    local sep = value:match("^%-%s") and "%s+%-%s+" or "%s*,%s*"
    value = value:gsub("^%-%s+", "")
    for item in (value .. (sep == "%s*,%s*" and "," or " - ")):gmatch("(.-)" .. sep) do
        if item ~= "" then
            table.insert(items, item)
        end
    end
    return items
end

--- Reads the number a frontmatter value carries ('0064' is "64"); nil when it
--- carries none.
---@param value string|nil
---@return string|nil
function M.number(value)
    local digits = value and value:match("(%d+)")
    return digits and number(digits) or nil
end

return M

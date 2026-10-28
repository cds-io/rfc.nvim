-- Reads a report's JSON record from EveryCRSReport.com for what the HTML
-- lacks: the newest version's files, the links back to the original, how
-- many versions there are and since when, and the topics. The record is
--
--   { "id": "R43397", "versions": [ { "date": "2026-10-27",
--       "sourceLink": "https://www.congress.gov/crs-product/R43397",
--       "formats": [ { "format": "PDF", "url": "…", "filename": "files/…pdf" },
--                    { "format": "HTML", "filename": "files/…html" } ], … },
--       … older versions … ],
--     "topics": [ "Appropriations" ] }
--
-- newest version first. Plain busted has no JSON reader, and four fields
-- from a fixed shape need none: a brace walk finds each object of an array,
-- and patterns read the fields inside one. `rfc.source.crs.facts` carries
-- the result into the stored text.
---@class rfc.source.crs.version
local M = {}

---@class rfc.source.crs.Version
---@field number string        -- as the site spells it: R43397
---@field date string          -- YYYY-MM-DD of the newest version
---@field count integer        -- how many versions the record lists
---@field first string         -- YYYY-MM-DD of the oldest
---@field html string|nil      -- the mirror's HTML file of the newest version: files/…html
---@field mirror string|nil    -- the mirror's PDF copy: files/…pdf
---@field pdf string|nil       -- the publisher's PDF
---@field source string|nil    -- the publisher's product page
---@field topics string[]

local REFUSED = "not a CRS report record"

--- The objects of the JSON array opening at `open` (the position of its
--- `[`), each as its text, by walking braces outside strings.
---@param text string
---@param open integer
---@return string[]
local function objects(text, open)
    local out, depth, start, in_string, i = {}, 0, nil, false, open + 1
    while i <= #text do
        local c = text:sub(i, i)
        if in_string then
            if c == "\\" then
                i = i + 1
            elseif c == '"' then
                in_string = false
            end
        elseif c == '"' then
            in_string = true
        elseif c == "{" then
            depth = depth + 1
            start = start or i
        elseif c == "}" then
            depth = depth - 1
            if depth == 0 and start then
                table.insert(out, text:sub(start, i))
                start = nil
            end
        elseif c == "]" and depth == 0 then
            break
        end
        i = i + 1
    end
    return out
end

--- A string field's value in an object's text, or nil.
---@param object string
---@param key string
---@return string|nil
local function field(object, key)
    return object:match('"' .. key .. '":%s*"([^"]*)"')
end

--- The `[` of the array a key opens in an object's text, or nil.
---@param object string
---@param key string
---@return integer|nil
local function array_at(object, key)
    local _, last = object:find('"' .. key .. '":%s*%[')
    return last
end

--- The files of a version's formats: `html` and `mirror` as the mirror
--- files them, `pdf` as the publisher serves it.
---@param version string
---@return { html: string|nil, mirror: string|nil, pdf: string|nil }
local function formats_of(version)
    local files = {}
    local open = array_at(version, "formats")
    for _, f in ipairs(open and objects(version, open) or {}) do
        local kind = field(f, "format")
        if kind == "HTML" then
            files.html = field(f, "filename")
        elseif kind == "PDF" then
            files.mirror = field(f, "filename")
            files.pdf = field(f, "url")
        end
    end
    return files
end

--- The strings of the record's top-level `topics` array, the last such
--- array in the text (each version carries its own, as objects, before it).
---@param text string
---@return string[]
local function topics_of(text)
    local inner = text:match('.*"topics":%s*%[(.-)%]')
    local out = {}
    for name in (inner or ""):gmatch('"([^"]*)"') do
        table.insert(out, name)
    end
    return out
end

--- The record read: nil and a message for a text that is not one.
---@param text string
---@return rfc.source.crs.Version|nil
---@return string|nil err
function M.version(text)
    local number = field(text, "id")
    local open = array_at(text, "versions")
    local versions = open and objects(text, open) or {}
    if not number or #versions == 0 then
        return nil, REFUSED
    end
    local newest, oldest = versions[1], versions[#versions]
    local files = formats_of(newest)
    return {
        number = number,
        date = field(newest, "date") or "",
        count = #versions,
        first = field(oldest, "date") or "",
        html = files.html,
        mirror = files.mirror,
        pdf = files.pdf,
        source = field(newest, "sourceLink"),
        topics = topics_of(text),
    }
end

return M

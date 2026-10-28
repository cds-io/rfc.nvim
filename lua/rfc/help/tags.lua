-- Shared tag names and tag-file syntax.
local fp = require("cds.fp")
local M = {}

--- Lowercase, with every run of characters outside [%w.-] collapsed to one
--- dash, so a title or a citation key spells a tag the help tag scanner
--- and the search command both accept.
---@param s string
---@return string
function M.slug(s)
    local out = s:lower():gsub("[^%w%.%-]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    return out
end
local slug = M.slug

--- The tag for a section: `rfc9110-3.1` for "3.1", `rfc9110-A` for appendix
--- A, and the slugged title for a part with no number (Index).
---@param rfc_num string
---@param number string
---@param title string
---@return string
function M.tag(rfc_num, number, title)
    return "rfc" .. rfc_num .. "-" .. (number ~= "" and number or slug(title))
end

--- The tag for an entry in the references: `rfc9110-ref-CACHING` for
--- "[CACHING]"; the case is kept because that is how the RFC spells it.
---@param rfc_num string
---@param citation string   -- with its brackets
---@return string
function M.ref_tag(rfc_num, citation)
    local key = citation:gsub("^%[", ""):gsub("%]$", ""):gsub("[^%w%.%-]+", "-")
    return "rfc" .. rfc_num .. "-ref-" .. key
end
-- What a tag looks like: a source prefix (three or four letters) and a
-- number (rfc9110, eip1559-abstract, erc20.txt, simd64-summary), the
-- prefix and -subjects (rfc-subjects.txt, rfc-subjects-web-http,
-- w3c-subjects-tags-wot: a prefix is three or four characters, a letter
-- at each end), or a shortname source's prefix and a document's shortname,
-- with # before a section (w3c-css-grid-2, w3c-css-grid-2#5.3,
-- crs-r43397#summary; a shortname may carry dashes of its own, as a legacy
-- CRS number does: crs-98-684). These are the shapes every render declares
-- and no text contains by accident: the shortname shape is spelled per
-- prefix, since any three letters and a dash (*not-a-tag*) would read as
-- one otherwise, so a new source keyed by shortname adds its prefix here.
local SHORTNAME = { "w3c", "crs" }

---@param suffix string
---@return string[]
local function shortname_shapes(suffix)
    local out = {}
    for _, prefix in ipairs(SHORTNAME) do
        table.insert(out, prefix .. "%-[%l%d%-%.]+" .. suffix)
    end
    return out
end

M.TAG = { "%l%l%l%l?%d[%w%.%-]*", "%l[%l%d][%l%d]?%l%-subjects[%w%.%-]*", unpack(shortname_shapes("#?[%w%.%-]*")) }

-- A section tag: a tag with a dash and a name after its number
-- (rfc9110-3.1, eip1559-abstract), after -subjects (rfc-subjects-web),
-- or after a shortname's # (w3c-css-grid-2#5.3). The file tags and the
-- reference entries' tags are not sections.
M.SECTION = {
    "%l%l%l%l?%d+%-[%w%.%-]*",
    "%l[%l%d][%l%d]?%l%-subjects%-[%w%.%-]*",
    unpack(shortname_shapes("#[%w%.%-]+")),
}

--- The tags a rendered document carries: every `*tag*` of a shape in TAG,
--- in line order. The store reads every document back through this to
--- rebuild the tags file.
---@param lines string[]
---@return rfc.HelpTag[]
function M.tags_in(lines)
    local tags = {}
    for i, line in ipairs(lines) do
        local found = {}
        for _, pattern in ipairs(M.TAG) do
            local from = 1
            while true do
                local first, last, name = line:find("%*(" .. pattern .. ")%*", from)
                if not first then
                    break
                end
                table.insert(found, { at = first, name = name })
                from = last + 1
            end
        end
        table.sort(found, function(x, y)
            return x.at < y.at
        end)
        -- a tag two shapes read (w3c-subjects fits the subjects shape and
        -- the w3c shape) is one tag
        local last_at
        for _, f in ipairs(found) do
            if f.at ~= last_at then
                table.insert(tags, { name = f.name, line = i })
            end
            last_at = f.at
        end
    end
    return tags
end

--- The section tag ending the line, or nil: a shape in SECTION between
--- stars at the end, and not a reference entry's tag.
---@param line string
---@return string|nil
function M.section_tag(line)
    return fp.find_map(M.SECTION, function(pattern)
        local tag = line:match("%*(" .. pattern .. ")%*$")
        if tag and not tag:match("^%l+%d+%-ref%-") and not tag:match("#ref%-") then
            return tag
        end
    end)
end

--- A contents row's indent and the section tag it links, or nil for any
--- other line.
---@param line string
---@return string|nil indent
---@return string|nil tag
function M.row_tag(line)
    local found = fp.find_map(M.SECTION, function(pattern)
        local indent, tag = line:match("^(%s*)|(" .. pattern .. ")|")
        return tag and { indent, tag } or nil
    end)
    if found then
        return found[1], found[2]
    end
end

--- The lines of a help tags file for the documents given, byte-sorted as
--- Vim's tag search expects. The search command is the tag between stars,
--- which only a heading carries; stray stars in an RFC's text never enter
--- this file, which is why the file is written here and not by :helptags.
---@param docs { file: string, tags: rfc.HelpTag[] }[]
---@return string[]
function M.tags_file(docs)
    local lines = {}
    for _, doc in ipairs(docs) do
        for _, tag in ipairs(doc.tags) do
            table.insert(lines, tag.name .. "\t" .. doc.file .. "\t/*" .. tag.name .. "*")
        end
    end
    table.sort(lines)
    return lines
end

return M

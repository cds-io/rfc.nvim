-- Source document identity and picker labels.
local M = {}

--- A document's tag: the prefix and the id, joined with a dash for a
--- source that goes by shortname (w3c-wcag22) and directly otherwise
--- (rfc9110).
---@param source rfc.Source
---@param id string
---@return string
function M.tag_of(source, id)
    return source.key == "shortname" and (source.prefix .. "-" .. id) or (source.prefix .. id)
end

--- The id a tag of the source carries, or nil for a subjects tag: the
--- number after the prefix, or the shortname before the section's #. A
--- file tag (w3c-wcag22.txt) names its document; a versioned shortname
--- keeps its dot (did-resolution-1.0).
---@param source rfc.Source
---@param tag string
---@return string|nil
function M.id_of(source, tag)
    if tag:match("^%l[%l%d]-%l%-subjects") then
        return nil
    end
    if source.key == "shortname" then
        return (tag:gsub("%.txt$", "")):match("^" .. source.prefix .. "%-([^#]+)")
    end
    return tag:match("^%l+0*(%d+)")
end
--- How the picker and completion show an entry: its tag, then its title,
--- so the tag is the first word of whatever the reader picks.
---@param source rfc.Source
---@param entry rfc.Entry
---@return string
function M.label(source, entry)
    return M.tag_of(source, entry.id) .. "  " .. entry.label
end

return M

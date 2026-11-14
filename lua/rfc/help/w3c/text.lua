-- Report image URLs and mention links.
local M = {}

--- The image URL made absolute against the report's.
---@param src string
---@param url string   -- the report's URL, with or without its trailing slash
---@return string
local function absolute(src, url)
    if src:match("^https?://") then
        return src
    elseif src:match("^/") then
        return "https://www.w3.org" .. src
    end
    return (url:match("/$") and url or url .. "/") .. src
end

--- The text with its mentions as links, last to first so the earlier
--- spans stay where they were.
---@param t rfc.source.html.Text
---@param ctx table
---@return string
local function link(t, ctx)
    local s = t.text
    for i = #t.mentions, 1, -1 do
        local m = t.mentions[i]
        local tag
        if m.kind == "section" then
            tag = ctx.sections[m.section]
        elseif m.kind == "report" then
            tag = "w3c-" .. m.id:lower()
        elseif m.kind == "tag" then
            tag = m.id
        elseif m.kind == "reference" then
            tag = ctx.refs[m.id:lower()]
        end
        if tag then
            s = s:sub(1, m.first - 1) .. "|" .. tag .. "|" .. s:sub(m.last + 1)
        end
    end
    return s
end

M.absolute, M.link = absolute, link

return M

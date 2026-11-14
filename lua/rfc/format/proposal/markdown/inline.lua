-- Markdown inline text as plain text: markup and inline HTML dropped, entities unescaped.
local M = {}

local ENTITIES =
    { ["&amp;"] = "&", ["&lt;"] = "<", ["&gt;"] = ">", ["&quot;"] = '"', ["&#39;"] = "'", ["&nbsp;"] = " " }

---@param s string
---@return string
function M.unescape(s)
    return (s:gsub("&[%w#]+;", function(e)
        return ENTITIES[e] or e
    end))
end

--- Turns markdown inline markup and inline HTML into plain text: tags are
--- dropped (a <code> span becomes backticks), entities unescaped, **bold** and
--- *em* reduced to their text. A code span is kept as written, and so is an
--- autolink (<https://...>), which is no tag.
---@param s string
---@return string
function M.plain(s)
    local spans = {}
    s = s:gsub("`[^`]*`", function(span)
        table.insert(spans, span)
        return "\1" .. #spans .. "\1"
    end)
    s = s:gsub("<code>(.-)</code>", "`%1`")
    s = s:gsub("</?%a[%w%-]*%s[^>]*>", ""):gsub("</?%a[%w%-]*/?>", "")
    s = M.unescape(s)
    s = s:gsub("%*%*([^*]-)%*%*", "%1")
    s = s:gsub("%*([^%s*][^*]-)%*", "%1")
    return (s:gsub("\1(%d+)\1", function(n)
        return spans[tonumber(n)]
    end))
end

return M

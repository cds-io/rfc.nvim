-- Reads the W3C technical reports index (www.w3.org/TR): `index` answers one
-- entry per shortname with the facts the page lists, and `short_group` writes
-- a working group's name the W3C's own short way. Every function takes
-- strings and answers tables, so the specs run under plain busted.
local html = require("rfc.source.html")
local tree = require("rfc.source.html.tree")
local fp = require("cds.fp")

local plain, classes, find_all = tree.plain, tree.classes, tree.find_all

---@class rfc.sources.w3c.reader
local M = {}

---@class rfc.sources.w3c.reader.Entry
---@field shortname string   -- as the URL spells it: WCAG22
---@field id string          -- lowercased: wcag22
---@field url string         -- https://www.w3.org/TR/WCAG22/
---@field title string
---@field date string|nil    -- YYYY-MM-DD, from the entry's time
---@field maturity string    -- "" when the entry has none
---@field tags string[]
---@field groups string[]

--- Reads one entry from one `div.tr-list__item`, or nil when it names no
--- report.
---@param item table
---@return rfc.sources.w3c.reader.Entry|nil
local function entry(item)
    local link = find_all(item, function(n)
        return n.name == "a" and (n.attrs.href or ""):match("^https://www%.w3%.org/TR/[^/]+/?$") ~= nil
    end)[1]
    if not link then
        return nil
    end
    local url = link.attrs.href
    local shortname = url:match("/TR/([^/]+)")
    local time = find_all(item, function(n)
        return n.name == "time"
    end)[1]
    local maturity = find_all(item, function(n)
        return classes(n)["maturity-level"]
    end)[1]
    local tags, groups = {}, {}
    -- the dl's rows: a dt names what its dd lists
    for _, dl in
        ipairs(find_all(item, function(n)
            return n.name == "dl"
        end))
    do
        local what
        for _, child in ipairs(dl.children) do
            if type(child) ~= "string" then
                for _, c in ipairs(child.name == "div" and child.children or { child }) do
                    if type(c) ~= "string" and c.name == "dt" then
                        what = html.squash(plain(c))
                    elseif type(c) ~= "string" and c.name == "dd" then
                        if what == "Tags" then
                            for tag in plain(c):gmatch("[^,]+") do
                                table.insert(tags, html.squash(tag))
                            end
                        elseif what == "Deliverers" then
                            for _, a in
                                ipairs(find_all(c, function(n)
                                    return n.name == "a"
                                end))
                            do
                                table.insert(groups, html.squash(plain(a)))
                            end
                        end
                    end
                end
            end
        end
    end
    return {
        shortname = shortname,
        id = shortname:lower(),
        url = url,
        title = html.squash(plain(link)),
        date = time and time.attrs.datetime or nil,
        maturity = maturity and html.squash(plain(maturity)) or "",
        tags = fp.filter(tags, function(t)
            return t ~= ""
        end),
        groups = groups,
    }
end

--- Reads the index: one entry per shortname, the first of a duplicate winning.
---@param lines string[]
---@return rfc.sources.w3c.reader.Entry[]
function M.index(lines)
    local root = tree.of(lines)
    local items = find_all(root, function(n)
        return n.name == "div" and classes(n)["tr-list__item"]
    end)
    local entries = {}
    for _, item in ipairs(items) do
        local e = entry(item)
        if e then
            table.insert(entries, e)
        end
    end
    return fp.unique(entries, function(e)
        return e.id
    end)
end

-- The kinds of group the W3C charters, and the shorthand it writes them with.
local GROUP_KINDS = {
    { " Working Group$", " WG" },
    { " Interest Group$", " IG" },
    { " Community Group$", " CG" },
    { " Business Group$", " BG" },
}

--- Shortens a group's kind the W3C's own way: "Cascading Style Sheets (CSS)
--- Working Group" becomes "Cascading Style Sheets (CSS) WG"; a name of another
--- shape (Advisory Board, Technical Architecture Group) stays as written.
---@param name string
---@return string
function M.short_group(name)
    for _, kind in ipairs(GROUP_KINDS) do
        local short, n = name:gsub(kind[1], kind[2])
        if n > 0 then
            return short
        end
    end
    return name
end

return M

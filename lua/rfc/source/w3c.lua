-- Reads the W3C technical reports index (www.w3.org/TR): `index` answers one
-- entry per shortname with the facts the page lists, and `short_group` writes
-- a working group's name the W3C's own short way. `date_time`,
-- `parse_http_time` and `http_time` convert the dates the plugin compares, an
-- index date against a report's Last-Modified header. Every function takes
-- strings and answers tables, so the specs run under plain busted.
local html = require("rfc.source.html")
local tree = require("rfc.source.html.tree")
local fp = require("cds.fp")

local plain, classes, find_all = tree.plain, tree.classes, tree.find_all

---@class rfc.source.w3c
local M = {}

---@class rfc.source.w3c.Entry
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
---@return rfc.source.w3c.Entry|nil
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
---@return rfc.source.w3c.Entry[]
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

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local MONTH_INDEX = {}
for i, m in ipairs(MONTHS) do
    MONTH_INDEX[m] = i
end
local DAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }

--- Converts a UTC date-time table to seconds since the epoch. os.time reads a
--- table as local time; the zone's offset at that very time (daylight saving
--- included) is taken from the round trip through os.date.
---@param t table   -- year, month, day, hour, min, sec
---@return integer
local function utc_time(t)
    t.isdst = false
    local guess = os.time(t)
    local back = os.date("!*t", guess) --[[@as osdate]]
    back.isdst = false
    return guess + (os.time(t) - os.time(back))
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

--- Converts an index date to seconds since the epoch at noon UTC.
---@param date string   -- YYYY-MM-DD
---@return integer
function M.date_time(date)
    local y, m, d = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    return utc_time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12, min = 0, sec = 0 })
end

--- Reads an HTTP date ("Mon, 04 Dec 2023 05:07:44 GMT") as seconds since the
--- epoch, or nil when it does not read.
---@param s string
---@return integer|nil
function M.parse_http_time(s)
    local d, mon, y, hh, mm, ss = s:match("^%a+, (%d+) (%a+) (%d+) (%d+):(%d+):(%d+) GMT$")
    if not d or not MONTH_INDEX[mon] then
        return nil
    end
    return utc_time({
        year = tonumber(y),
        month = MONTH_INDEX[mon],
        day = tonumber(d),
        hour = tonumber(hh),
        min = tonumber(mm),
        sec = tonumber(ss),
    })
end

--- Writes seconds since the epoch as an HTTP date.
---@param t integer
---@return string
function M.http_time(t)
    local u = os.date("!*t", t)
    return ("%s, %02d %s %04d %02d:%02d:%02d GMT"):format(
        DAYS[u.wday],
        u.day,
        MONTHS[u.month],
        u.year,
        u.hour,
        u.min,
        u.sec
    )
end

return M

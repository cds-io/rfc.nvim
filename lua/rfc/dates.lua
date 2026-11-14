-- The dates the plugin compares: an index's date (YYYY-MM-DD) against a
-- copy's time on disk and an HTTP Last-Modified header, and back again for
-- an If-Modified-Since request. Every time is seconds since the epoch; every
-- conversion reads and writes UTC, whatever zone the editor runs in.
local M = {}

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

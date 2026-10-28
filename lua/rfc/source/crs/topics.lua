-- Reads EveryCRSReport.com's topic pages, which together list every
-- US Congressional Research Service report the site mirrors. The source fetches
-- the 32 pages and joins them into one text, each page behind a marker line
-- (`marker`), so one cached file is both the index and the taxonomy. A page
-- is one `div.crs-report` per report:
--
--   <div class="crs-report">
--     <p class="report-title"><a href="/reports/R42853.html">Nuclear Energy: Overview of Congressional Issues</a></p>
--     <p class="report-metadata">
--       December 11, 2012 &ndash;
--       October 22, 2026
--       <code>R42853</code>
--     </p>
--   </div>
--
-- A report revised once or more shows two dates; one never revised shows
-- one. The reading is string patterns over the lines, not the element tree:
-- the joined pages run to 24 MB, and three facts per block need no tree.
-- Every function takes strings and answers tables, so the specs run under
-- plain busted.
local html = require("rfc.source.html")

---@class rfc.source.crs.topics
local M = {}

---@class rfc.source.crs.Entry
---@field number string      -- as the site spells it: R42853, 98-35
---@field id string          -- lowercased: r42853
---@field title string
---@field first string|nil   -- YYYY-MM-DD of the first version, when the block shows two dates
---@field latest string      -- YYYY-MM-DD of the newest version

---@class rfc.source.crs.Topic
---@field slug string        -- economic-policy
---@field name string        -- Economic Policy, from the page's heading
---@field entries rfc.source.crs.Entry[]

local MONTHS = {
    January = 1,
    February = 2,
    March = 3,
    April = 4,
    May = 5,
    June = 6,
    July = 7,
    August = 8,
    September = 9,
    October = 10,
    November = 11,
    December = 12,
}
local MONTH_NAMES = {}
for name, n in pairs(MONTHS) do
    MONTH_NAMES[n] = name
end

--- The line the source writes before each page it joins.
---@param slug string
---@return string
function M.marker(slug)
    return "<!-- crs-topic: " .. slug .. " -->"
end

--- The slug a marker line carries, or nil for any other line.
---@param line string
---@return string|nil
local function marked(line)
    return line:match("^<!%-%- crs%-topic: ([%w%-]+) %-%->$")
end

--- A page's long date ("October 22, 2026") as YYYY-MM-DD, or nil.
---@param text string
---@return string|nil
function M.date(text)
    local month, day, year = text:match("(%a+)%s+(%d+),%s+(%d%d%d%d)")
    local m = month and MONTHS[month]
    if not m then
        return nil
    end
    return ("%s-%02d-%02d"):format(year, m, tonumber(day))
end

--- A YYYY-MM-DD date written the page's long way: March 9, 2016.
---@param iso string
---@return string
function M.long_date(iso)
    local y, m, d = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then
        return iso
    end
    return ("%s %d, %s"):format(MONTH_NAMES[tonumber(m)] or m, tonumber(d), y)
end

--- The product a report number names, from its prefix: the site's own
--- names for the current series, Legacy for the numbered 1990s series, the
--- lettered ones (IB, TE, IS, IG, IP, MB) and the mirror's junk ids.
---@param number string
---@return "Report"|"In Focus"|"Insight"|"Legal Sidebar"|"Legacy"
function M.kind(number)
    if number:match("^RL?%d") or number:match("^RS%d") then
        return "Report"
    elseif number:match("^IF%d") then
        return "In Focus"
    elseif number:match("^IN%d") then
        return "Insight"
    elseif number:match("^LSB%d") then
        return "Legal Sidebar"
    end
    return "Legacy"
end

--- Reads one page's lines into its topic: the name from the `<h1>`, an
--- entry per report block. A block's title line opens it; the dates and
--- the number follow on the next lines, the number closing it.
---@param slug string
---@param lines string[]
---@return rfc.source.crs.Topic
local function page(slug, lines)
    local topic = { slug = slug, name = "", entries = {} }
    local open = nil
    for _, line in ipairs(lines) do
        local h1 = line:match("<h1>(.-)</h1>")
        if h1 and topic.name == "" then
            topic.name = html.decode(h1)
        end
        local number, title = line:match('<a href="/reports/([^"/]+)%.html">(.-)</a>')
        if number then
            open = { number = number, id = number:lower(), title = html.decode(title), dates = {} }
        elseif open then
            local date = M.date(line)
            if date then
                table.insert(open.dates, date)
            end
            local code = line:match("<code>([^<]+)</code>")
            if code then
                local entry = { number = open.number, id = open.id, title = open.title }
                entry.latest = open.dates[#open.dates] or ""
                entry.first = #open.dates > 1 and open.dates[1] or nil
                table.insert(topic.entries, entry)
                open = nil
            end
        end
    end
    return topic
end

--- The topics of the joined index, one per marker, in order.
---@param lines string[]
---@return rfc.source.crs.Topic[]
function M.topics(lines)
    local topics, slug, buffer = {}, nil, {}
    local function flush()
        if slug then
            table.insert(topics, page(slug, buffer))
        end
    end
    for _, line in ipairs(lines) do
        local next_slug = marked(line)
        if next_slug then
            flush()
            slug, buffer = next_slug, {}
        else
            table.insert(buffer, line)
        end
    end
    flush()
    return topics
end

--- Every report once, the first page listing it giving its facts, with the
--- names of every topic that lists it, in page order.
---@param lines string[]
---@return (rfc.source.crs.Entry|{ topics: string[] })[]
function M.index(lines)
    local entries, by_id = {}, {}
    for _, topic in ipairs(M.topics(lines)) do
        for _, e in ipairs(topic.entries) do
            local seen = by_id[e.id]
            if not seen then
                seen =
                    { number = e.number, id = e.id, title = e.title, first = e.first, latest = e.latest, topics = {} }
                by_id[e.id] = seen
                table.insert(entries, seen)
            end
            table.insert(seen.topics, topic.name)
        end
    end
    return entries
end

return M

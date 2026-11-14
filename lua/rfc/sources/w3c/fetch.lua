-- A W3C technical report, asked conditionally, as a Task. A spec replaces the functions
-- below with Tasks of fixture text.
local Task = require("cds.task")
local http = require("cds.http")
local status = http.status
local dates = require("rfc.dates")
local fetch = require("rfc.fetch")

local M = {}

--- A W3C technical report by its URL, asked conditionally when the copy's
--- time is given: a 304 answers false (unchanged); a 200 answers the body
--- with the server's Last-Modified as the time to stamp the copy with (now,
--- when the server sends none); a 404 is the report not existing.
---@param url string         -- https://www.w3.org/TR/WCAG22/, the index's spelling
---@param shortname string   -- for the message
---@param since integer|nil  -- the copy's time
---@return cds.Task
function M.w3c(url, shortname, since)
    return Task.new(function()
        local headers = since and { ["If-Modified-Since"] = dates.http_time(since) } or nil
        local res, err = http.request({ method = "GET", url = url, headers = headers, timeout = 30 })
        if not res then
            assert(err, "a refused request carries its error")
            return nil, ("W3C %s: %s"):format(shortname, err.message)
        end
        if res.status == status.NOT_MODIFIED then
            return false
        end
        if res.status ~= status.OK then
            return nil, fetch.describe({ status = res.status }, "W3C " .. shortname)
        end
        local modified = res.headers["last-modified"] and dates.parse_http_time(res.headers["last-modified"])
        return { body = res.body, modified = modified or os.time() }
    end)
end

return M

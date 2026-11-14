-- A CRS report's record and file on EveryCRSReport.com, as Tasks. A spec replaces the functions
-- below with Tasks of fixture text.
local fetch = require("rfc.fetch")

local M = {}

local CRS = "https://www.everycrsreport.com/"

--- A CRS report's JSON record on EveryCRSReport.com, by its number as the
--- site spells it (uppercase).
---@param number string   -- R43397
---@return cds.Task
function M.crs_json(number)
    return fetch.text(CRS .. "reports/" .. number .. ".json", "CRS " .. number)
end

--- A CRS report's HTML rendering, by the file name its record gives.
---@param filename string   -- files/2026-10-27_R43397_<sha1>.html
---@param number string     -- for the message
---@return cds.Task
function M.crs_html(filename, number)
    return fetch.text(CRS .. filename, "CRS " .. number)
end

return M

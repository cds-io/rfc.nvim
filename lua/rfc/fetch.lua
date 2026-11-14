-- The network, as Tasks: a GET, a listing page, and the pieces a source's
-- own fetch module builds on (request, text, describe). Each source's
-- documents come through its fetch module (rfc.sources.<prefix>.fetch). A
-- spec replaces the functions below with Tasks of fixture text.
local Task = require("cds.task")
local http = require("cds.http")
local status = http.status

local M = {}

M.github_raw = "https://raw.githubusercontent.com/"

--- A GET, run now: the body, or nil and a transport failure's message or
--- a status but 200 as `{ status }`.
---@param url string
---@return string|nil body
---@return any err
function M.request(url)
    local res, err = http.request({ method = "GET", url = url, timeout = 30 })
    if not res then
        assert(err, "a refused request carries its error")
        return nil, err.message
    end
    if res.status ~= status.OK then
        return nil, { status = res.status }
    end
    return res.body
end

--- A GET as a Task of the body.
---@param url string
---@return cds.Task
function M.get(url)
    return Task.new(function()
        return M.request(url)
    end)
end

--- The refusal as a sentence: a 404 is the thing not existing.
---@param err any
---@param what string
---@return string
function M.describe(err, what)
    if type(err) == "table" and err.status == status.NOT_FOUND then
        return what .. " does not exist"
    elseif type(err) == "table" then
        return ("HTTP %d fetching %s"):format(err.status, what)
    end
    return ("%s: %s"):format(what, tostring(err))
end

---@param url string
---@param what string
---@return cds.Task
function M.text(url, what)
    return M.get(url):map_err(function(err)
        return M.describe(err, what)
    end)
end

--- A listing page, every proposal under its status.
---@param url string
---@param what string
---@return cds.Task
function M.listing(url, what)
    return M.text(url, what)
end

return M

-- The network, as Tasks: the RFC editor's text for one RFC and its index.
-- A spec replaces `rfc` and `index` with Tasks of fixture text.
local Task = require("cds.task")
local http = require("cds.http")

local M = {}

M.base_url = "https://www.rfc-editor.org/"

--- A GET as a Task of the body. A transport failure refuses with its
--- message; any status but 200 refuses with the status.
---@param url string
---@return cds.Task
function M.get(url)
    return Task.new(function()
        local res, err = http.request({ method = "GET", url = url, timeout = 30 })
        if not res then
            return nil, err.message
        end
        if res.status ~= 200 then
            return nil, { status = res.status }
        end
        return res.body
    end)
end

--- The refusal as a sentence: a 404 is the thing not existing.
---@param err any
---@param what string
---@return string
local function describe(err, what)
    if type(err) == "table" and err.status == 404 then
        return what .. " does not exist"
    elseif type(err) == "table" then
        return ("HTTP %d fetching %s"):format(err.status, what)
    end
    return ("%s: %s"):format(what, tostring(err))
end

---@param rfc_num string
---@return cds.Task  -- of the text as one string
function M.rfc(rfc_num)
    return M.get(M.base_url .. "rfc/rfc" .. rfc_num .. ".txt"):recover(function(err)
        return Task.fail(describe(err, "RFC " .. rfc_num))
    end)
end

---@return cds.Task  -- of the index text as one string
function M.index()
    return M.get(M.base_url .. "rfc-index.txt"):recover(function(err)
        return Task.fail(describe(err, "the RFC index"))
    end)
end

return M

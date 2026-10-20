-- The network, as Tasks: the RFC Editor's text and index, and the Ethereum
-- proposals' repositories and listing pages. A spec replaces the four
-- functions below with Tasks of fixture text.
local Task = require("cds.task")
local http = require("cds.http")

local M = {}

M.rfc_editor = "https://www.rfc-editor.org/"
M.github_raw = "https://raw.githubusercontent.com/"

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

---@param url string
---@param what string
---@return cds.Task
local function text(url, what)
    return M.get(url):recover(function(err)
        return Task.fail(describe(err, what))
    end)
end

---@param rfc_num string
---@return cds.Task  -- of the text as one string
function M.rfc(rfc_num)
    return text(M.rfc_editor .. "rfc/rfc" .. rfc_num .. ".txt", "RFC " .. rfc_num)
end

---@return cds.Task  -- of the index text as one string
function M.index()
    return text(M.rfc_editor .. "rfc-index.txt", "the RFC index")
end

--- A proposal's markdown from its repository: ethereum/EIPs keeps
--- EIPS/eip-N.md and ethereum/ERCs keeps ERCS/erc-N.md.
---@param repo string   -- "ethereum/EIPs"
---@param dir string    -- "EIPS"
---@param prefix string -- "eip"
---@param id string
---@return cds.Task
function M.proposal(repo, dir, prefix, id)
    local url = ("%s%s/master/%s/%s-%s.md"):format(M.github_raw, repo, dir, prefix, id)
    return text(url, prefix:upper() .. " " .. id)
end

--- A listing page, every proposal under its status.
---@param url string
---@param what string
---@return cds.Task
function M.listing(url, what)
    return text(url, what)
end

return M

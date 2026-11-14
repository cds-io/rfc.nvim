-- A Bitcoin proposal's text from bitcoin/bips, as a Task. A spec replaces the functions
-- below with Tasks of fixture text.
local Task = require("cds.task")
local status = require("cds.http").status
local fetch = require("rfc.fetch")

local M = {}

--- A Bitcoin proposal's text from bitcoin/bips, filed as bip-0032.mediawiki
--- or, for the few written in markdown, bip-0032.md; the second is asked
--- for when the first is not there.
---@param id string
---@return cds.Task
function M.bip(id)
    local base = ("%sbitcoin/bips/master/bip-%04d."):format(fetch.github_raw, tonumber(id))
    return Task.new(function()
        local body, err = fetch.request(base .. "mediawiki")
        if not body and type(err) == "table" and err.status == status.NOT_FOUND then
            body, err = fetch.request(base .. "md")
        end
        if not body then
            return nil, fetch.describe(err, "BIP " .. id)
        end
        return body
    end)
end

return M

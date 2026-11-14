-- An Ethereum proposal's markdown from its repository, as a Task. A spec replaces the functions
-- below with Tasks of fixture text.
local fetch = require("rfc.fetch")

local M = {}

--- A proposal's markdown from its repository: ethereum/EIPs keeps
--- EIPS/eip-N.md and ethereum/ERCs keeps ERCS/erc-N.md.
---@param repo string   -- "ethereum/EIPs"
---@param dir string    -- "EIPS"
---@param prefix string -- "eip"
---@param id string
---@return cds.Task
function M.proposal(repo, dir, prefix, id)
    local url = ("%s%s/master/%s/%s-%s.md"):format(fetch.github_raw, repo, dir, prefix, id)
    return fetch.text(url, prefix:upper() .. " " .. id)
end

return M

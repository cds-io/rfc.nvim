-- Pure cache freshness and derived-input rules.
local fp = require("cds.fp")
local M = {}

--- Whether a fetched file is fresh: it exists, with a max_age it is
--- younger than it, and with a modification time the index knows it is
--- no older than that.
---@param mtime integer|nil    -- the file's, nil when there is none
---@param now integer
---@param max_age integer|nil  -- seconds; nil never ages
---@param modified integer|nil -- when the index says the thing changed; nil when it does not say
---@return boolean
function M.fresh(mtime, now, max_age, modified)
    if mtime == nil then
        return false
    end
    if modified ~= nil and modified > mtime then
        return false
    end
    return max_age == nil or (now - mtime) < max_age
end

--- Whether a derived document is current: it exists by the current
--- version, and is no older than each input, every one of which is still
--- good (on disk, and fresh when it ages).
---@param mtime integer|nil        -- the document's, nil when there is none
---@param version_ok boolean       -- whether its footer names the current render
---@param inputs (integer|false)[] -- each input's mtime, false for one missing or no longer fresh
---@return boolean
function M.current(mtime, version_ok, inputs)
    if mtime == nil or not version_ok then
        return false
    end
    return fp.all(inputs, function(input)
        return input and input <= mtime
    end)
end

return M

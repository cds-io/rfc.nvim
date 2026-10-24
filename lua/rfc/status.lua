-- The status axis: where a source's documents stand in their lifecycle
-- (Draft, Review, Final), the statuses an index holds in the lifecycle's
-- order, the cycle through them, and the one status a source's subjects
-- document is filtered to this session. Nothing here touches the editor.
local fp = require("cds.fp")

local M = {}

--- The status chosen for each source this session, by prefix: a status,
--- or false for All; a source not here has made no choice and takes the
--- reader's default. The subjects document on disk carries whichever
--- status rendered it, so a choice that differs renders it again.
---@type table<string, string|false>
M.chosen = {}

--- Records the choice: a status, or nil for All.
---@param prefix string
---@param status string|nil
function M.set(prefix, status)
    M.chosen[prefix] = status or false
end

--- The status the source's document is filtered to: the choice made this
--- session, else the default given; nil is All.
---@param prefix string
---@param default string|nil
---@return string|nil
function M.get(prefix, default)
    local chosen = M.chosen[prefix]
    if chosen == nil then
        return default
    end
    return chosen or nil
end

--- The statuses the entries stand in, each with its count: the
--- lifecycle's order first, any status outside it after, by name.
---@param order string[]        -- the lifecycle, as the source declares it
---@param entries { status: string|nil }[]
---@return { name: string, count: integer }[]
function M.counts(order, entries)
    local counts = fp.reduce(entries, {}, function(acc, e)
        if e.status then
            acc[e.status] = (acc[e.status] or 0) + 1
        end
        return acc
    end)
    local known = fp.filter(order, function(name)
        return counts[name] ~= nil
    end)
    local in_order = fp.set(order, function(name)
        return name
    end)
    local rest = fp.unique(
        fp.filter_map(entries, function(e)
            return e.status and not in_order[e.status] and e.status or nil
        end),
        function(name)
            return name
        end
    )
    table.sort(rest)
    local names = fp.reduce(rest, known, function(acc, name)
        acc[#acc + 1] = name
        return acc
    end)
    return fp.map(names, function(name)
        return { name = name, count = counts[name] }
    end)
end

--- The status as the lifecycle spells it, case aside; a name outside the
--- lifecycle as written.
---@param order string[]
---@param name string|nil
---@return string|nil
function M.named(order, name)
    return name and (fp.find(order, function(s)
        return s:lower() == name:lower()
    end) or name)
end

--- The status after `current` in the cycle: All (nil), then each in
--- order, then All again.
---@param order string[]
---@param current string|nil
---@return string|nil
function M.next(order, current)
    if current == nil then
        return order[1]
    end
    -- false marks the last status found, whose successor is All
    local after = fp.find_map(order, function(name, i)
        if name == current then
            return order[i + 1] or false
        end
    end)
    if after == nil then
        return order[1]
    end
    return after or nil
end

return M

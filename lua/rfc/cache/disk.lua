-- Disk reads and memoization by source revision.
local revision = require("rfc.revision")
local M = {}

--- Writes the lines, making the directory first: the reader may delete
--- the cache to start over while the editor runs.
---@param path string
---@param lines string[]
---@return true|nil, string|nil
local function write(path, lines)
    return require("cds.persist").write_lines(path, lines)
end

---@param path string
---@return integer|nil
local function mtime_of(path)
    local stat = vim.uv.fs_stat(path)
    return stat and stat.mtime.sec or nil
end

-- One parse per file and name, kept while the file's revision is the one
-- it was parsed at.
local parsed = require("cds.fp").memoize(function(path, _, parse)
    local snapshot = revision.read(path)
    if not snapshot then
        return nil
    end
    return parse(snapshot.lines)
end, {
    slot = function(path, name)
        return path .. "\0" .. name
    end,
    key = function(path)
        return revision.of(path)
    end,
})

--- `parse` over the file's lines, once per revision of the file under
--- `name`; nil when there is no file.
---@param path string
---@param name string
---@param parse fun(lines: string[]): any
---@return any|nil
local function memo_of(path, name, parse)
    if not revision.of(path) then
        return nil
    end
    return parsed(path, name, parse)
end

M.write, M.mtime, M.memo = write, mtime_of, memo_of

return M

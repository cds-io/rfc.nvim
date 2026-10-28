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

-- Memos, one per file and name: the exact revision parsed and its answer.
local memos = {}

--- `parse` over the file's lines, once per revision of the file under
--- `name`; nil when there is no file.
---@param path string
---@param name string
---@param parse fun(lines: string[]): any
---@return any|nil
local function memo_of(path, name, parse)
    local key, stamp = path .. "\0" .. name, revision.of(path)
    if not stamp then
        memos[key] = nil
        return nil
    end
    local memo = memos[key]
    if not memo or memo.revision ~= stamp then
        local snapshot = revision.read(path)
        if not snapshot then
            return nil
        end
        memo = { revision = snapshot.revision, value = parse(snapshot.lines) }
        memos[key] = memo
    end
    return memo.value
end

M.write, M.mtime, M.memo = write, mtime_of, memo_of

return M

-- File identity for parsing, distinct from second-resolution freshness ages.
local M = {}

---@class rfc.SourceSnapshot
---@field lines string[]
---@field revision? string -- identity of the file these lines were read from

---@param path string
---@return string?
function M.of(path)
    local stat = vim.uv.fs_stat(path)
    if not stat then
        return nil
    end
    return table.concat(
        { stat.dev, stat.ino, stat.size, stat.mtime.sec, stat.mtime.nsec, stat.ctime.sec, stat.ctime.nsec },
        ":"
    )
end

--- Pair a read with its identity; retry a concurrent replacement rather than
--- label old bytes with a newer file's revision. Callers retain this snapshot.
---@param path string
---@return rfc.SourceSnapshot?, string?
function M.read(path)
    for _ = 1, 3 do
        local before = M.of(path)
        if not before then
            return nil, "missing source input: " .. path
        end
        local ok, lines = pcall(vim.fn.readfile, path)
        if not ok then
            return nil, tostring(lines)
        end
        if before == M.of(path) then
            return { lines = lines, revision = before }
        end
    end
    return nil, "source changed while reading: " .. path
end

return M

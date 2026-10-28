-- Clears one source's files from the cache: its texts (rfc9110.txt,
-- eip1559.md), its documents (doc/rfc9110.txt), its index files
-- (eip-categories.html, rfc-index.txt, rfc-subjects.csv) and its subjects
-- document (doc/rfc-subjects.txt), then the tags file rebuilt from the
-- documents left. Every file a source owns is named by one of its tags or
-- by its prefix and a dash, which is how `rfc.sources.of` reads a tag, so
-- ownership is that one question asked of each file's base name; doc/tags
-- and the other sources' files answer no.
local config = require("rfc.config")
local store = require("rfc.store")
local sources = require("rfc.sources")
local fp = require("cds.fp")
local result = require("cds.result")

local M = {}

--- The names in `names` whose base (the name without its last extension)
--- `of` answers with `source`.
---@param source rfc.Source
---@param names string[]
---@param of fun(tag: string): rfc.Source|nil
---@return string[]
function M.owned(source, names, of)
    return fp.filter(names, function(name)
        local base = name:match("^(.+)%.[^.]+$")
        return base ~= nil and of(base) == source
    end)
end

--- Every file directly under a directory, by name.
---@param dir string
---@return string[]
local function files_in(dir)
    return fp.filter_map(vim.fn.glob(dir .. "/*", false, true), function(path)
        return vim.fn.isdirectory(path) == 0 and vim.fn.fnamemodify(path, ":t") or nil
    end)
end

--- Deletes the source's files under the root and the doc directory and
--- rebuilds the tags file: how many went, or nil and the first path that
--- would not go.
---@param source rfc.Source
---@return integer|nil
---@return string|nil err
function M.clear(source)
    local cfg = config.get()
    local root, docs = store.root(cfg), store.doc_dir(cfg)
    local paths = {}
    for _, dir in ipairs({ root, docs }) do
        for _, name in ipairs(M.owned(source, files_in(dir), sources.of)) do
            table.insert(paths, dir .. "/" .. name)
        end
    end
    local gone, err = result.traverse(paths, function(path)
        if vim.fn.delete(path) ~= 0 then
            return nil, "could not delete " .. path
        end
        return true
    end)
    if not gone then
        return nil, err
    end
    if #paths > 0 then
        local ok, werr = store.write_tags(cfg)
        if not ok then
            return nil, werr
        end
    end
    return #paths
end

return M

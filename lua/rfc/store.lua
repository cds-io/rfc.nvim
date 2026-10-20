-- The store: each document's text as fetched and its help document on
-- disk, under one directory that doubles as a runtimepath entry, so
-- `:help rfc9110` is Neovim reading its own doc/ layout. The tags file is
-- written here from the documents' own tags; see help.tags_file for why
-- :helptags is not run. Documents are named by their tag: rfc9110, eip1559.
local help = require("rfc.help")

local M = {}

local INDEX_MAX_AGE = 24 * 60 * 60 -- seconds; a day-old index is fetched again

-- Roots already appended to the runtimepath, so a second setup() adds nothing.
local registered = {}

---@param cfg rfc.Config
---@return string
function M.root(cfg)
    return cfg.cache_dir or (vim.fn.stdpath("cache") .. "/rfc")
end

---@param cfg rfc.Config
---@return string
function M.doc_dir(cfg)
    return M.root(cfg) .. "/doc"
end

---@param cfg rfc.Config
---@param name string   -- the document's tag: rfc9110
---@param ext string    -- the extension the source's text uses
---@return string
function M.raw_path(cfg, name, ext)
    return M.root(cfg) .. "/" .. name .. "." .. ext
end

---@param cfg rfc.Config
---@param name string
---@return string
function M.doc_path(cfg, name)
    return M.doc_dir(cfg) .. "/" .. name .. ".txt"
end

--- Whether the document is on disk.
---@param cfg rfc.Config
---@param name string
---@return boolean
function M.has(cfg, name)
    return vim.fn.filereadable(M.doc_path(cfg, name)) == 1
end

--- The doc directory exists and the root is on the runtimepath. Documents
--- of the retired erc source go, since the eip documents now define the
--- alias tags they carried and two definitions of one tag make :help pick
--- whichever sorts first.
---@param cfg rfc.Config
function M.register(cfg)
    local root = M.root(cfg)
    vim.fn.mkdir(M.doc_dir(cfg), "p")
    local stale = vim.fn.glob(M.doc_dir(cfg) .. "/erc[0-9]*.txt", false, true)
    vim.list_extend(stale, vim.fn.glob(root .. "/erc[0-9]*.md", false, true))
    if #stale > 0 then
        for _, path in ipairs(stale) do
            vim.fn.delete(path)
        end
        M.write_tags(cfg)
    end
    if not registered[root] then
        vim.opt.runtimepath:append(root)
        registered[root] = true
    end
end

---@param path string
---@param lines string[]
---@return true|nil, string|nil
local function write(path, lines)
    if vim.fn.writefile(lines, path) == -1 then
        return nil, "could not write " .. path
    end
    return true
end

--- Rebuilds doc/tags from every document in the directory.
---@param cfg rfc.Config
---@return true|nil, string|nil
function M.write_tags(cfg)
    local docs = {}
    for _, path in ipairs(vim.fn.glob(M.doc_dir(cfg) .. "/*.txt", false, true)) do
        table.insert(docs, { file = vim.fn.fnamemodify(path, ":t"), tags = help.tags_in(vim.fn.readfile(path)) })
    end
    return write(M.doc_dir(cfg) .. "/tags", help.tags_file(docs))
end

--- Writes the text and its document, then the tags file.
---@param cfg rfc.Config
---@param name string
---@param ext string
---@param raw string[]
---@param doc rfc.HelpDoc
---@return true|nil, string|nil
function M.write(cfg, name, ext, raw, doc)
    M.register(cfg)
    local ok, err = write(M.raw_path(cfg, name, ext), raw)
    if not ok then
        return nil, err
    end
    ok, err = write(M.doc_path(cfg, name), doc.lines)
    if not ok then
        return nil, err
    end
    return M.write_tags(cfg)
end

---@param cfg rfc.Config
---@param file string   -- the source's index file name
---@return string
function M.index_path(cfg, file)
    return M.root(cfg) .. "/" .. file
end

--- The cached index and whether it is fresh; nil when there is none.
---@param cfg rfc.Config
---@param file string
---@param now? integer   -- seconds; os.time() unless a spec sets one
---@return string[]|nil lines
---@return boolean fresh
function M.read_index(cfg, file, now)
    local path = M.index_path(cfg, file)
    local stat = vim.uv.fs_stat(path)
    if not stat then
        return nil, false
    end
    return vim.fn.readfile(path), ((now or os.time()) - stat.mtime.sec) < INDEX_MAX_AGE
end

---@param cfg rfc.Config
---@param file string
---@param lines string[]
---@return true|nil, string|nil
function M.write_index(cfg, file, lines)
    M.register(cfg)
    return write(M.index_path(cfg, file), lines)
end

return M

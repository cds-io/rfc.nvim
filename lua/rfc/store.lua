-- The store: each document's text as fetched and its help document on
-- disk, under one directory that doubles as a runtimepath entry, so
-- `:help rfc9110` is Neovim reading its own doc/ layout. The tags file is
-- written here from the documents' own tags; see help.tags_file for why
-- :helptags is not run. Documents are named by their tag: rfc9110, eip1559.
local help = require("rfc.help")
local result = require("cds.result")

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

--- Whether the document is on disk and rendered by the current render.
---@param cfg rfc.Config
---@param name string
---@return boolean
function M.has(cfg, name)
    local path = M.doc_path(cfg, name)
    if vim.fn.filereadable(path) ~= 1 then
        return false
    end
    return help.render_of(vim.fn.readfile(path)) == help.RENDER
end

--- The stored text, as fetched, or nil when there is none.
---@param cfg rfc.Config
---@param name string
---@param ext string
---@return string[]|nil
function M.raw(cfg, name, ext)
    local path = M.raw_path(cfg, name, ext)
    if vim.fn.filereadable(path) ~= 1 then
        return nil
    end
    return vim.fn.readfile(path)
end

-- What an earlier layout of the cache left that the current one would
-- misread, retired when the store registers: a glob under the root and
-- the reason. A layout change names its files anew and lists the old
-- names here, so a copy from before is never read as the new shape.
-- stylua: ignore
local RETIRED = {
    { glob = "doc/erc[0-9]*.txt", why = "the eip documents define the erc alias tags, and two definitions of one tag make :help pick whichever sorts first" },
    { glob = "erc[0-9]*.md", why = "the texts of the retired erc documents" },
    { glob = "eip-index.html", why = "the two all pages, whose rows name no category; the index of the category pages is eip-categories.html" },
}

--- Deletes what one retirement names under the root: how many went, or
--- nil and the path that would not.
---@param root string
---@param entry { glob: string, why: string }
---@return integer|nil, string|nil
local function retire(root, entry)
    local paths = vim.fn.glob(root .. "/" .. entry.glob, false, true)
    for _, path in ipairs(paths) do
        if vim.fn.delete(path) ~= 0 then
            return nil, "could not retire " .. path
        end
    end
    return #paths
end

--- The doc directory exists and the root is on the runtimepath, with what
--- earlier layouts left retired first: one fold over RETIRED, stopping at
--- the first path that will not go, then the tags file rebuilt when any
--- did. The runtimepath is registered either way; the refusal is the
--- caller's to report.
---@param cfg rfc.Config
---@return true|nil, string|nil
function M.register(cfg)
    local root = M.root(cfg)
    vim.fn.mkdir(M.doc_dir(cfg), "p")
    local counts, err = result.traverse(RETIRED, function(entry)
        return retire(root, entry)
    end)
    local ok, werr = result.bind(counts, err, function(c)
        local gone = 0
        for _, n in ipairs(c) do
            gone = gone + n
        end
        if gone == 0 then
            return true
        end
        return M.write_tags(cfg)
    end)
    if not registered[root] then
        vim.opt.runtimepath:append(root)
        registered[root] = true
    end
    return ok, werr
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

--- Writes a document alone, then the tags file: for a document whose raw
--- is an index the store already keeps (a source's subjects).
---@param cfg rfc.Config
---@param name string
---@param doc rfc.HelpDoc
---@return true|nil, string|nil
function M.write_doc(cfg, name, doc)
    M.register(cfg)
    local ok, err = write(M.doc_path(cfg, name), doc.lines)
    if not ok then
        return nil, err
    end
    return M.write_tags(cfg)
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
    return M.write_doc(cfg, name, doc)
end

--- Whether the document is in the store by the current render and no
--- older than the index file it was rendered from.
---@param cfg rfc.Config
---@param name string
---@param file string   -- the index file name
---@return boolean
function M.has_since(cfg, name, file)
    if not M.has(cfg, name) then
        return false
    end
    local doc = vim.uv.fs_stat(M.doc_path(cfg, name))
    local index = vim.uv.fs_stat(M.index_path(cfg, file))
    return doc ~= nil and index ~= nil and doc.mtime.sec >= index.mtime.sec
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

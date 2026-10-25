-- The store: the cache directory's layout, which doubles as a runtimepath
-- entry, so `:help rfc9110` is Neovim reading its own doc/ layout. The
-- paths live here (a document's text, its document, an index), the tags
-- file is written here from the documents' own tags (see help.tags_file
-- for why :helptags is not run), and what an earlier layout left is
-- retired here. What is on disk and when it is produced again is the
-- cache's (rfc.cache). Documents are named by their tag: rfc9110, eip1559.
local help = require("rfc.help")
local result = require("cds.result")
local fp = require("cds.fp")

local M = {}

-- Roots already appended to the runtimepath, so a second setup() adds nothing.
local registered = {}

--- A fingerprint of the lua tree under `root`: the first twelve hex digits
--- of a SHA-256 over every .lua file's relative path and content, in path
--- order. Any change to the code that renders changes it, so a cached
--- document's render is compared against the code and not a number.
---@param root string   -- the plugin's directory
---@return string
function M.render_version(root)
    local files = vim.fn.glob(root .. "/lua/**/*.lua", true, true)
    table.sort(files)
    local parts = fp.map(files, function(path)
        return path:sub(#root + 2) .. "\n" .. table.concat(vim.fn.readfile(path, "b"), "\n")
    end)
    return vim.fn.sha256(table.concat(parts, "\0")):sub(1, 12)
end

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
    local gone, err = result.traverse(paths, function(path)
        if vim.fn.delete(path) ~= 0 then
            return nil, "could not retire " .. path
        end
        return true
    end)
    return gone and #paths or nil, err
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
        local gone = fp.reduce(c, 0, function(sum, n)
            return sum + n
        end)
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
    return require("cds.persist").write_lines(path, lines)
end

--- Rebuilds doc/tags from every document in the directory.
---@param cfg rfc.Config
---@return true|nil, string|nil
function M.write_tags(cfg)
    local docs = fp.map(vim.fn.glob(M.doc_dir(cfg) .. "/*.txt", false, true), function(path)
        return { file = vim.fn.fnamemodify(path, ":t"), tags = help.tags_in(vim.fn.readfile(path)) }
    end)
    return write(M.doc_dir(cfg) .. "/tags", help.tags_file(docs))
end

--- Writes a document, then the tags file.
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

---@param cfg rfc.Config
---@param file string   -- the source's index file name
---@return string
function M.index_path(cfg, file)
    return M.root(cfg) .. "/" .. file
end

return M

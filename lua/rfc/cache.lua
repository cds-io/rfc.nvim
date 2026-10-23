-- The cache as declared entries. Everything under the cache root is one of
-- three things: a fetched file, served from disk while young enough and
-- produced otherwise (an index, a document's text); a derived document,
-- rebuilt when its render is older than the current one or an input is
-- newer (a document, a source's subjects); and a memo, a parse of a file
-- redone when the file changes (what completion offers). An entry answers
-- Tasks, so a derived document composes over its inputs with bind, and a
-- new cached thing is declared, never reimplemented. The two rules, fresh
-- and current, are pure; the entries are a rim over the store's paths.
local store = require("rfc.store")
local help = require("rfc.help")
local fp = require("cds.fp")

-- cds.task reaches for vim.async when it loads, so the plain tier, which
-- runs the two rules below, gets it on first use instead; task() answers
-- the module
local function task()
    return require("cds.task")
end

local M = {}

--- Whether a fetched file is fresh: it exists and, with a max_age, is
--- younger than it.
---@param mtime integer|nil   -- the file's, nil when there is none
---@param now integer
---@param max_age integer|nil -- seconds; nil never ages
---@return boolean
function M.fresh(mtime, now, max_age)
    if mtime == nil then
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

--- Writes the lines, making the directory first: the reader may delete
--- the cache to start over while the editor runs.
---@param path string
---@param lines string[]
---@return true|nil, string|nil
local function write(path, lines)
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    if vim.fn.writefile(lines, path) == -1 then
        return nil, "could not write " .. path
    end
    return true
end

---@param path string
---@return integer|nil
local function mtime_of(path)
    local stat = vim.uv.fs_stat(path)
    return stat and stat.mtime.sec or nil
end

-- Memos, one per file and name: the mtime parsed and the parse's answer.
local memos = {}

--- `parse` over the file's lines, once per mtime of the file under
--- `name`; nil when there is no file.
---@param path string
---@param name string
---@param parse fun(lines: string[]): any
---@return any|nil
local function memo_of(path, name, parse)
    local mtime = mtime_of(path)
    if not mtime then
        return nil
    end
    local key = path .. "\0" .. name
    local memo = memos[key]
    if not memo or memo.mtime ~= mtime then
        memo = { mtime = mtime, value = parse(vim.fn.readfile(path)) }
        memos[key] = memo
    end
    return memo.value
end

---@class rfc.Fetched
---@field cfg rfc.Config
---@field file string                 -- under the root: rfc-subjects.csv, rfc9110.txt
---@field produce fun(): cds.Task     -- of the body as one string
---@field max_age integer|nil         -- seconds; nil never ages
---@field label string                -- the subject of messages: "the RFC index", "RFC 9110"
---@field notify nil|fun(msg: string, level: integer)  -- where the stale warning goes; silent without
---@field placeholder nil|fun(lines: string[]): boolean  -- a copy that stands in for the thing is produced again
local Fetched = {}
Fetched.__index = Fetched

---@return string
function Fetched:path()
    return store.index_path(self.cfg, self.file)
end

---@return integer|nil
function Fetched:mtime()
    return mtime_of(self:path())
end

--- Stats only.
---@param now? integer
---@return boolean
function Fetched:fresh(now)
    return M.fresh(self:mtime(), now or os.time(), self.max_age)
end

--- The copy on disk, fresh or stale; nil when there is none or it is a
--- placeholder.
---@return string[]|nil
function Fetched:cached()
    local path = self:path()
    if vim.fn.filereadable(path) ~= 1 then
        return nil
    end
    local lines = vim.fn.readfile(path)
    if self.placeholder and self.placeholder(lines) then
        return nil
    end
    return lines
end

--- The lines: the copy while fresh; else produced, cleaned, written and
--- answered, and when producing fails with a copy on disk, that copy with
--- a warning. The copy is read before producing: a failure may be met in
--- a fast event, where a file cannot be read.
---@return cds.Task
function Fetched:lines()
    local cached = self:cached()
    if cached and self:fresh() then
        return task().of(cached)
    end
    return self.produce()
        :map(help.clean)
        :on_main()
        :bind_result(function(lines)
            local ok, err = write(self:path(), lines)
            return ok and lines or nil, err
        end)
        :recover(function(err)
            if not cached then
                return task().fail(err)
            end
            if self.notify then
                self.notify(
                    ("%s could not be refreshed (%s); using the stale copy"):format(self.label, tostring(err)),
                    vim.log.levels.WARN
                )
            end
            return task().of(cached)
        end)
end

--- `parse` over the copy on disk (fresh or stale), once per mtime of the
--- file under `name`; nil when there is no copy.
---@param name string
---@param parse fun(lines: string[]): any
---@return any|nil
function Fetched:memo(name, parse)
    return memo_of(self:path(), name, parse)
end

---@param cfg rfc.Config
---@param spec { file: string, produce: fun(): cds.Task, max_age?: integer, label: string, notify?: fun(msg: string, level: integer), placeholder?: fun(lines: string[]): boolean }
---@return rfc.Fetched
function M.fetched(cfg, spec)
    return setmetatable({
        cfg = cfg,
        file = spec.file,
        produce = spec.produce,
        max_age = spec.max_age,
        label = spec.label,
        notify = spec.notify,
        placeholder = spec.placeholder,
    }, Fetched)
end

---@class rfc.Derived
---@field cfg rfc.Config
---@field name string             -- the document's name: rfc9110, rfc-subjects
---@field from rfc.Fetched[]      -- the inputs, in the order produce receives them
---@field version integer         -- the render the document must carry
---@field produce fun(...: string[]): rfc.HelpDoc|nil, string|nil
---@field limit integer|nil       -- how many inputs are produced at once; all without
local Derived = {}
Derived.__index = Derived

---@return string
function Derived:path()
    return store.doc_path(self.cfg, self.name)
end

--- Stats and the document's last line; an input that is no longer fresh
--- counts as missing, so a day-old index rebuilds its document.
---@return boolean
function Derived:current()
    local path = self:path()
    local mtime = mtime_of(path)
    local version_ok = mtime ~= nil and help.render_of(vim.fn.readfile(path, "", -1)) == self.version
    local inputs = fp.map(self.from, function(input)
        return input:fresh() and input:mtime() or false
    end)
    return M.current(mtime, version_ok, inputs)
end

--- The name, at once when current; else the inputs' lines, the document
--- produced on the main loop and written with the tags file.
---@return cds.Task
function Derived:ensure()
    if self:current() then
        return task().of(self.name)
    end
    local tasks = fp.map(self.from, function(input)
        return input:lines()
    end)
    if self.limit then
        -- a semaphore shared across the batch: the inputs may be a
        -- hundred proposals, and the network is asked `limit` at a time
        local permits = require("cds.async").semaphore(self.limit)
        tasks = fp.map(tasks, function(t)
            return t:limited(permits)
        end)
    end
    return task().all(tasks):on_main():bind_result(function(inputs)
        local doc, err = self.produce(unpack(inputs, 1, inputs.n or #inputs))
        if not doc then
            return nil, err
        end
        local ok, werr = store.write_doc(self.cfg, self.name, doc)
        return ok and self.name or nil, werr
    end)
end

--- `parse` over the document's lines, once per mtime of the document
--- under `name`; nil before it exists.
---@param name string
---@param parse fun(lines: string[]): any
---@return any|nil
function Derived:memo(name, parse)
    return memo_of(self:path(), name, parse)
end

---@param cfg rfc.Config
---@param spec { name: string, from: rfc.Fetched[], version: integer, produce: fun(...: string[]): rfc.HelpDoc|nil, string|nil, limit?: integer }
---@return rfc.Derived
function M.derived(cfg, spec)
    return setmetatable({
        cfg = cfg,
        name = spec.name,
        from = spec.from,
        version = spec.version,
        produce = spec.produce,
        limit = spec.limit,
    }, Derived)
end

return M

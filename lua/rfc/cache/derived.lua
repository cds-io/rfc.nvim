-- Derived help exports over fetched snapshots.
local store = require("rfc.store")
local help = require("rfc.help")
local fp = require("cds.fp")
local disk = require("rfc.cache.disk")
local mtime_of, memo_of = disk.mtime, disk.memo
local rules = require("rfc.cache.rules")
local models = require("rfc.cache.models")
local source_key, prepare_model = models.key, models.prepare
local function task()
    return require("cds.task")
end

local M = {}

---@alias rfc.PreparationContext string|(fun(): string?)

---@class rfc.Derived
---@field cfg rfc.Config
---@field name string             -- the document's name: rfc9110, rfc-subjects
---@field from rfc.Fetched[]      -- the inputs, in the order produce receives them
---@field version string          -- the render the document must carry
---@field produce nil|fun(...: string[]): rfc.HelpDoc|nil, string|nil
---@field prepare nil|fun(...: string[]): rfc.SourceModel|nil, string|nil
---@field render_model nil|fun(model: rfc.SourceModel): rfc.HelpDoc|nil, string|nil
---@field context rfc.PreparationContext? -- extra preparation dependencies, such as the report URL
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
    local exported = models.exported_key(path)
    if exported and exported ~= source_key(self) then
        return false
    end
    local mtime = mtime_of(path)
    local version_ok = mtime ~= nil and help.render_of(vim.fn.readfile(path, "", -1)) == self.version
    local inputs = fp.map(self.from, function(input)
        return input:fresh() and input:mtime() or false
    end)
    return rules.current(mtime, version_ok, inputs)
end

--- The name, at once when current; else the inputs' lines, the document
--- produced on the main loop and written with the tags file.
---@return cds.Task
function Derived:ensure()
    if self:current() then
        return task().of(self.name)
    end
    local tasks = fp.map(self.from, function(input)
        return input:snapshot()
    end)
    if self.limit then
        -- a semaphore shared across the batch: the inputs may be a
        -- hundred proposals, and the network is asked `limit` at a time
        local permits = require("cds.async").semaphore(self.limit)
        tasks = fp.map(tasks, function(t)
            return t:limited(permits)
        end)
    end
    return task().all(tasks):on_main():bind_result(function(snapshots)
        local key = source_key(self, snapshots)
        local inputs = { n = snapshots.n or #snapshots }
        for i = 1, inputs.n do
            inputs[i] = snapshots[i].lines
        end
        local doc, err
        if self.render_model then
            local model
            model, err = prepare_model(self, inputs, key)
            if not model then
                return nil, err
            end
            doc, err = self.render_model(model)
        else
            doc, err = assert(self.produce, "derived entry supplies a renderer")(unpack(inputs, 1, inputs.n or #inputs))
        end
        if not doc then
            return nil, err
        end
        local ok, werr = store.write_doc(self.cfg, self.name, doc)
        if ok and self.render_model then
            models.export(self:path(), key)
        end
        return ok and self.name or nil, werr
    end)
end

Derived.source_model = models.source_model
--- under `name`; nil before it exists.
---@param name string
---@param parse fun(lines: string[]): any
---@return any|nil
function Derived:memo(name, parse)
    return memo_of(self:path(), name, parse)
end

---@param cfg rfc.Config
---@param spec { name: string, from: rfc.Fetched[], version: string, produce?: (fun(...: string[]): rfc.HelpDoc|nil, string|nil), render_model?: (fun(model: rfc.SourceModel): rfc.HelpDoc|nil, string|nil), context?: rfc.PreparationContext, prepare?: (fun(...: string[]): rfc.SourceModel|nil, string|nil), limit?: integer }
---@return rfc.Derived
function M.derived(cfg, spec)
    return setmetatable({
        cfg = cfg,
        name = spec.name,
        from = spec.from,
        version = spec.version,
        produce = spec.produce,
        prepare = spec.prepare,
        render_model = spec.render_model,
        context = spec.context,
        limit = spec.limit,
    }, Derived)
end

return M

-- Prepared source models and their ordered input identity.
local revision = require("rfc.revision")
local fp = require("cds.fp")

local M = {}

---@type table<string, string> -- identity used by the last successful help export
local exported_sources = {}
---@type table<string, string> -- identity the held plan was prepared under
local prepared_keys = {}

---@param entry rfc.Derived
---@param snapshots? rfc.SourceSnapshot[]
---@return string?
local function source_key(entry, snapshots)
    local context = entry.context
    if type(context) == "function" then
        context = context()
    end
    local parts = { entry.version, context or "" }
    for i, input in ipairs(entry.from) do
        if type(input.path) ~= "function" then
            return nil
        end
        local path = input:path()
        local stamp = snapshots and snapshots[i].revision or nil
        if not snapshots then
            stamp = revision.of(path)
        end
        if not stamp then
            return nil
        end
        parts[#parts + 1], parts[#parts + 2] = path, stamp
    end
    return table.concat(parts, "\0")
end

---@param entry rfc.Derived
---@param inputs { [integer]: string[], n?: integer }
---@return rfc.SourceModel?, string?
local function compute(entry, inputs)
    if entry.prepare then
        return entry.prepare(unpack(inputs, 1, inputs.n or #inputs))
    end
    local doc, err = assert(entry.produce, "derived entry supplies prepare or produce")(unpack(inputs))
    local model = doc and doc.model
    return model, err or (not model and "source model not available" or nil)
end

-- One plan per derived path, kept while the inputs' identity (version,
-- context, each input's path and revision) is the one it was prepared
-- under; a failed preparation is never kept.
local remembered, memo = fp.memoize(function(entry, inputs, _)
    return compute(entry, inputs)
end, {
    slot = function(entry)
        return entry:path()
    end,
    key = function(_, _, key)
        return key
    end,
})

---@param entry rfc.Derived
---@param inputs { [integer]: string[], n?: integer }
---@param key string?   -- the inputs' identity; without one the plan is prepared and not kept
---@return rfc.SourceModel?, string?
local function prepare_model(entry, inputs, key)
    if not key then
        return compute(entry, inputs)
    end
    local model, err = remembered(entry, inputs, key)
    if model then
        prepared_keys[entry:path()] = key
    end
    return model, err
end
--- The pure source plan for the inputs already ensured on disk. Reuses the
--- plan prepared for help, or reads and prepares it once for a warm disk cache.
--- Version, context and ordered input identities invalidate it automatically.
--- This never parses the generated help file or performs network work.
---@return rfc.SourceModel|nil, string|nil
function M.source_model(self)
    local key = source_key(self)
    if key and memo.held(self, nil, key) then
        return remembered(self, nil, key)
    end
    local inputs, snapshots = {}, {}
    for _, input in ipairs(self.from) do
        local snapshot
        if type(input.cached_snapshot) == "function" then
            snapshot = input:cached_snapshot()
        else
            local lines = input:cached()
            snapshot = lines and { lines = lines } or nil
        end
        if not snapshot then
            return nil, "missing source input: " .. (input.file or "(unnamed)")
        end
        inputs[#inputs + 1], snapshots[#snapshots + 1] = snapshot.lines, snapshot
    end
    return prepare_model(self, inputs, source_key(self, snapshots))
end

--- Whether the entry's plan is held under its current identity, so a
--- source_model answers without reading or preparing.
---@param entry rfc.Derived
---@return boolean
function M.held(entry)
    local key = source_key(entry)
    return key ~= nil and memo.held(entry, nil, key)
end

--- Drops every held plan; the spec harness's way to a cold session.
function M.forget_all()
    memo.forget()
    prepared_keys = {}
end

--- The identity the path's document stands at: its last export's, or the
--- held plan's.
---@param path string
---@return string?
function M.exported_key(path)
    return exported_sources[path] or prepared_keys[path]
end

function M.export(path, key)
    exported_sources[path] = key
end

M.key, M.prepare = source_key, prepare_model

return M

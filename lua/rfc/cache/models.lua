-- Prepared source models and their ordered input identity.
local revision = require("rfc.revision")

local M = {}

-- One immutable plan per derived path, reused across short-lived descriptors.
-- A version/context/input identity change replaces it; missing inputs and failed
-- preparations never leave an older plan available under a new identity.
---@type table<string, {key: string, model: rfc.SourceModel}>
local source_models = {}
---@type table<string, string> -- identity used by the last successful help export
local exported_sources = {}

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
---@param key string?
---@return rfc.SourceModel?, string?
local function prepare_model(entry, inputs, key)
    local path = entry:path()
    local held = source_models[path]
    if key and held and held.key == key then
        return held.model
    end
    source_models[path] = nil
    local model, err
    if entry.prepare then
        model, err = entry.prepare(unpack(inputs, 1, inputs.n or #inputs))
    else
        local doc
        doc, err = assert(entry.produce, "derived entry supplies prepare or produce")(unpack(inputs))
        model = doc and doc.model
        err = err or (not model and "source model not available" or nil)
    end
    if model and key then
        source_models[path] = { key = key, model = model }
    end
    return model, err
end
--- The pure source plan for the inputs already ensured on disk. Reuses the
--- plan prepared for help, or reads and prepares it once for a warm disk cache.
--- Version, context and ordered input identities invalidate it automatically.
--- This never parses the generated help file or performs network work.
---@return rfc.SourceModel|nil, string|nil
function M.source_model(self)
    local key, path = source_key(self), self:path()
    local held = source_models[path]
    if key and held and held.key == key then
        return held.model
    end
    source_models[path] = nil
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
    local key, held = source_key(entry), source_models[entry:path()]
    return key ~= nil and held ~= nil and held.key == key
end

--- Drops every held plan; the spec harness's way to a cold session.
function M.forget_all()
    source_models = {}
end

function M.exported_key(path)
    local held = source_models[path]
    return exported_sources[path] or (held and held.key)
end

function M.export(path, key)
    exported_sources[path] = key
end

M.key, M.prepare = source_key, prepare_model

return M

-- Subjects preparation and cache dependency policies.
local config = require("rfc.config")
local cache = require("rfc.cache")
local help = require("rfc.help")
local subjects = require("rfc.subjects")
local cds_subjects = require("rfc.source.subjects")
local lifecycle = require("rfc.status")
local fp = require("cds.fp")
local metadata = require("rfc.app.entries")
local progress = require("rfc.app.progress")
local index_of, subjects_index_of, raw_of = metadata.index_of, metadata.subjects_index_of, metadata.raw_of
local with_status = metadata.with_status
local M = {}

--- A source's subjects document as a cache entry: over its subjects
--- index, or, for a source whose subjects are in its documents' texts,
--- over the text of every document the cached index names (none cached:
--- no inputs, and the document is not current until the index is).
--- Filtered to the status chosen for the source (the reader's default
--- before any choice): only the entries standing there are filed, the
--- title line says so, and the render version carries the status, so a
--- document rendered under another is rendered again. The source's index
--- says where each entry stands, so it joins the inputs when a status
--- filters.
---@param source rfc.Source
---@return rfc.Derived
function M.subjects_of(source)
    local s = assert(source.subjects, "a source with a subjects document declares its subjects")
    local status =
        lifecycle.named(source.status or {}, lifecycle.get(source.prefix, config.get().status[source.prefix]))
    local doc = { prefix = source.prefix, title = s.title, about = s.about, key = source.key, status = status }
    local name = source.prefix .. "-subjects"
    local version = help.RENDER .. subjects.suffix(status)
    if s.texts then
        local listed = index_of(source):memo("entries", source.entries) or {}
        local function prepare(...)
            local texts = { ... }
            local entries = fp.filter_map(listed, function(e, i)
                if not status or source.status_of(texts[i]) == status then
                    return s.entry(e.id, texts[i])
                end
            end)
            return subjects.model(doc, cds_subjects.tree(entries, s.roots))
        end
        return cache.derived(config.get(), {
            name = name,
            from = fp.map(listed, function(e)
                return raw_of(source, e.id)
            end),
            version = version,
            limit = 8,
            prepare = prepare,
            render_model = subjects.render_model,
        })
    end
    local from = { subjects_index_of(source) }
    if status then
        table.insert(from, index_of(source))
    end
    local function prepare(lines, index_lines)
        progress.phase(source.prefix, "parsing metadata")
        local entries, err = s.entries(lines)
        if not entries then
            return nil, err
        end
        progress.phase(source.prefix, "filing")
        if status then
            local standing = fp.set(
                fp.filter(with_status(source, source.entries(index_lines)), function(e)
                    return e.status == status
                end),
                function(e)
                    return e.id
                end
            )
            entries = fp.filter(entries, function(e)
                return standing[e.id] == true
            end)
        end
        return subjects.model(doc, cds_subjects.tree(entries, s.roots))
    end
    return cache.derived(config.get(), {
        name = name,
        from = from,
        version = version,
        prepare = prepare,
        render_model = subjects.render_model,
        phase = function(stage)
            progress.phase(source.prefix, stage)
        end,
    })
end

--- Whether a source's subjects need no fetch: its subjects index is
--- fresh, or, for subjects in the texts, its index is fresh and every
--- text it names is on disk.
---@param source rfc.Source
---@return boolean
function M.subjects_fresh(source)
    if not source.subjects.texts then
        return subjects_index_of(source):fresh()
    end
    return index_of(source):fresh()
        and fp.all(M.subjects_of(source).from, function(input)
            return input:mtime() ~= nil
        end)
end
--- The subjects document in the store: rendered from the subjects index
--- (the cached copy while it is a day old) unless it is already there by
--- the current render and no older than the index.
---@param source rfc.Source
---@return cds.Task  -- of the document's name
function M.ensure_subjects(source)
    if source.subjects.texts then
        -- the index first, since the document's inputs are what it names
        return index_of(source):lines():bind(function()
            return M.subjects_of(source):ensure()
        end)
    end
    return M.subjects_of(source):ensure()
end

return M

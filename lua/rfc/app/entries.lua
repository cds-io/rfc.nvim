-- Source cache descriptors and cached metadata lookups.
local config = require("rfc.config")
local cache = require("rfc.cache")
local help = require("rfc.help")
local w3c = require("rfc.source.w3c")
local fp = require("cds.fp")
local Task = require("cds.task")
local lifecycle = require("rfc.status")
local session = require("rfc.app.session")
local progress = require("rfc.app.progress")
local tag_of = require("rfc.app.names").tag_of
local M = {}

local entry_of

--- The text from the source: straight by number, or, for a source whose
--- index names each document's file, with the file its entry carries, the
--- index fetched first; `since` is the copy's time, for a source that asks
--- conditionally.
---@param source rfc.Source
---@param id string
---@param since integer|nil
---@return cds.Task  -- of the text as one string, or as the cache's produce answers
local function fetch_text(source, id, since)
    if not source.located then
        return source.fetch(id)
    end
    return M.index_lines(source):bind(function()
        local entry = entry_of(source, id)
        if not (entry and entry.file) then
            return Task.fail(("%s %s does not exist"):format(source.label, id))
        end
        return source.fetch(id, entry.file, since)
    end)
end

local DAY = 24 * 60 * 60

--- A source's index as a cache entry: kept a day, the stale copy with a
--- warning when the fetch fails.
---@param source rfc.Source
---@return rfc.Fetched
function M.index_of(source)
    return cache.fetched(config.get(), {
        file = source.index_file,
        produce = source.index,
        max_age = DAY,
        label = "the " .. source.label .. " index",
        notify = session.notify,
    })
end

--- A source's subjects index as a cache entry, kept like its index.
---@param source rfc.Source
---@return rfc.Fetched
function M.subjects_index_of(source)
    local s = assert(source.subjects, "a source with a subjects document declares its subjects")
    return cache.fetched(config.get(), {
        file = s.index_file,
        produce = s.index,
        max_age = DAY,
        label = "the " .. source.label .. " subjects index",
        notify = session.notify,
    })
end

--- The index's entry for a document, from the cached index, parsed once
--- per copy; nil without.
---@param source rfc.Source
---@param id string
---@return rfc.Entry|nil
entry_of = function(source, id)
    local entries = M.index_of(source):memo("entries", source.entries) or {}
    return fp.find(entries, function(e)
        return e.id == id
    end)
end

--- A document's text as a cache entry: it never ages, and a placeholder
--- (the stub a moved proposal leaves) is fetched again.
---@param source rfc.Source
---@param id string
---@return rfc.Fetched
function M.raw_of(source, id)
    local entry = source.key == "shortname" and entry_of(source, id) or nil
    return cache.fetched(config.get(), {
        file = tag_of(source, id) .. "." .. source.raw_ext,
        produce = function(since)
            return fetch_text(source, id, since)
        end,
        label = source.label .. " " .. id,
        placeholder = source.placeholder,
        -- a report republished after the copy was taken is asked for again
        modified = entry and entry.date and w3c.date_time(entry.date) or nil,
    })
end

--- A document as a cache entry over its text: rendered when missing, when
--- an older render wrote it, or when the text is newer.
---@param source rfc.Source
---@param id string
---@return rfc.Derived
function M.document_of(source, id)
    local function url()
        local entry = source.located and entry_of(source, id) or nil
        return entry and entry.file or nil
    end
    return cache.derived(config.get(), {
        name = tag_of(source, id),
        from = { M.raw_of(source, id) },
        version = help.RENDER,
        context = url,
        prepare = function(lines)
            return assert(source.prepare, "document source supplies a source plan")(id, lines, url())
        end,
        render_model = source.render_model,
        phase = function(stage)
            progress.phase(source.prefix, stage)
        end,
    })
end
--- The entries with their statuses: as the index gives them, or, for a
--- source whose index carries none, read from each cached text (an entry
--- whose text is not on disk has none yet).
---@param source rfc.Source
---@param entries rfc.Entry[]
---@return rfc.Entry[]
function M.with_status(source, entries)
    if not source.status_of then
        return entries
    end
    return fp.map(entries, function(e)
        local copy = vim.deepcopy(e)
        copy.status = M.raw_of(source, e.id):memo("status", source.status_of)
        return copy
    end)
end

--- The statuses a source's cached index places its entries in, with
--- counts, in lifecycle order; none before the index is on disk.
---@param source rfc.Source
---@return { name: string, count: integer }[]
function M.statuses_of(source)
    local entries = M.index_of(source):memo("entries", source.entries)
    return entries and lifecycle.counts(source.status, M.with_status(source, entries)) or {}
end
--- The document in the store: fetched, rendered and written when absent,
--- rendered again when an older render wrote it or its text is newer.
---@param source rfc.Source
---@param id string
---@return cds.Task  -- of the document's name
function M.ensure(source, id)
    return M.document_of(source, id):ensure()
end
--- A source's index as a Task of its lines: the cached copy while it is a
--- day old, fetched otherwise, and the stale copy when the fetch fails.
---@param source rfc.Source
---@return cds.Task
function M.index_lines(source)
    local index = M.index_of(source)
    -- the index fetch is the long wait (the CRS index is 32 pages), so it
    -- says so; a fresh copy reads silently
    if not index:fresh() then
        session.notify("fetching the " .. source.label .. " index")
        progress.phase(source.prefix, "reading source")
    end
    return index:lines()
end

M.entry_of = entry_of

return M

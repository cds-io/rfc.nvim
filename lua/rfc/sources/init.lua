-- The sources a document can come from, as a registry. A source registers a
-- spec (its identity and its command), which costs nothing: the record (where
-- its text and index come from, how its index reads, how its text renders)
-- is required the first time the source is used, and answers with the spec's
-- identity merged in, so the identity is written once. The rims read a record
-- without knowing which source they hold.
local fp = require("cds.fp")
local tags = require("rfc.help.tags")

local M = {}
local specs, records = {}, {}

local IDENTITY = { "prefix", "key", "aliases", "label", "command", "desc", "default_on", "module" }

--- Registers a source, or answers why not: a prefix taken by another module,
--- or a spec missing a field. Registering the same spec again replaces it.
---@param spec rfc.SourceSpec
---@return true|nil, string|nil
function M.register(spec)
    for _, field in ipairs({ "prefix", "label", "command", "desc", "module" }) do
        if type(spec[field]) ~= "string" then
            return nil, ("a source spec needs %s, a string"):format(field)
        end
    end
    local at = #specs + 1
    for i, s in ipairs(specs) do
        if s.prefix == spec.prefix then
            if s.module ~= spec.module then
                return nil, ("source %s is %s already; %s cannot take it"):format(spec.prefix, s.module, spec.module)
            end
            at = i
        end
    end
    local copy = { aliases = {} }
    for k, v in pairs(spec) do
        copy[k] = v
    end
    specs[at] = copy
    records[spec.prefix] = nil
    tags.set_shortnames(M.shortnames())
    return true
end

--- The registered specs, in registration order.
---@return rfc.SourceSpec[]
function M.specs()
    return specs
end

--- The prefixes of the sources a shortname names (w3c, crs).
---@return string[]
function M.shortnames()
    return fp.map(
        fp.filter(specs, function(s)
            return s.key == "shortname"
        end),
        function(s)
            return s.prefix
        end
    )
end

--- The source registered under the prefix, its record required on first use,
--- or nil.
---@param prefix string
---@return rfc.Source|nil
function M.get(prefix)
    if records[prefix] then
        return records[prefix]
    end
    local spec = fp.find(specs, function(s)
        return s.prefix == prefix
    end)
    if not spec then
        return nil
    end
    local record = require(spec.module)
    for _, field in ipairs(IDENTITY) do
        record[field] = spec[field]
    end
    records[prefix] = record
    return record
end

--- Every registered source, in registration order.
---@return rfc.Source[]
function M.all()
    return fp.map(specs, function(s)
        return M.get(s.prefix)
    end)
end

--- The source a tag belongs to, by its prefix or one of the aliases, or
--- nil: a document's tag (eip1559-abstract) or a subjects tag
--- (eip-subjects, eip-subjects-core).
---@param tag string
---@return rfc.Source|nil
function M.of(tag)
    -- the dashed form first, a prefix ending in a letter (w3c, rfc): the
    -- number form would read "w" from "w3c-…", and the dashed form must
    -- not read "rfc9110" from "rfc9110-3.1"
    local prefix = tag:match("^(%l[%l%d]-%l)%-") or tag:match("^(%l+)%d")
    if not prefix then
        return nil
    end
    local spec = fp.find(specs, function(s)
        return s.prefix == prefix or fp.any(s.aliases, function(alias)
            return alias == prefix
        end)
    end)
    return spec and M.get(spec.prefix)
end

return M

---@class rfc.Entry
---@field id string
---@field label string      -- what the picker shows after the tag
---@field text boolean      -- whether the source has a text to render (an RFC published as PDF only has none)
---@field date string|nil   -- YYYY-MM-DD, when the index dates the document (a W3C report's publication)
---@field file string|nil   -- the document's file as the index spells it (a proposal's path, a report's URL), for a source that is `located`
---@field status string|nil -- where the document stands in its lifecycle (Draft, Final), for a source with `status`

---@class rfc.Subjects
---@field index_file string|nil   -- the cache file the subjects index is stored as; the source's own index file when the index carries the subjects
---@field index nil|fun(): cds.Task   -- of the index text as one string
---@field entries nil|fun(lines: string[]): rfc.source.subjects.Entry[]|nil, string|nil  -- pure: the subjects from the index
---@field texts boolean|nil       -- the subjects come from the documents' own texts, every one the index names
---@field entry nil|fun(id: string, lines: string[]): rfc.source.subjects.Entry  -- pure: a document's subjects from its text
---@field title string            -- the document's title: RFCs by subject
---@field about string            -- the line naming the data
---@field roots string[]|nil      -- the roots first, in this order; the rest follow by name

---@class rfc.SourceSpec
---@field prefix string     -- the tag prefix: rfc, eip
---@field key "number"|"shortname"|nil  -- what names a document: a number (rfc9110) unless said; a shortname joins with a dash (w3c-wcag22)
---@field aliases string[]|nil  -- other prefixes whose tags this source answers: erc for eip
---@field label string      -- how a message names it: RFC, EIP
---@field command string    -- the command that opens it: Rfc
---@field desc string       -- the command's description
---@field default_on boolean|nil  -- whether the source is on when setup's `sources` leaves it unset
---@field module string     -- the record's module, required the first time the source is used

---@class rfc.Source: rfc.SourceSpec, rfc.SourceRecord  -- a registered source: its spec's identity merged over its record

---@class rfc.SourceRecord  -- what a source's module answers: how its texts and index are fetched, read and rendered
---@field raw_ext string    -- the extension the fetched text is stored under
---@field index_file string -- the cache file the index is stored as
---@field fetch fun(id: string, file?: string, since?: integer): cds.Task  -- of the text as one string; `file` is the entry's, for a located source; `since` the copy's time, for a source that asks conditionally
---@field located boolean|nil  -- the index names each document's file (its entries carry `file`), so a fetch goes through the index the rim keeps
---@field index fun(): cds.Task                    -- of the index text as one string
---@field entries fun(lines: string[]): rfc.Entry[]  -- pure
---@field prepare nil|fun(id: string, lines: string[], file?: string): rfc.SourceModel -- pure source plan
---@field render_model fun(model: rfc.SourceModel): rfc.HelpDoc
---@field render fun(id: string, lines: string[], file?: string): rfc.HelpDoc  -- pure, total; `file` is the entry's, for a located source
---@field placeholder nil|fun(lines: string[]): boolean  -- pure: whether a stored text stands in for the document rather than being it
---@field subjects nil|rfc.Subjects   -- the source's taxonomy, for a source that has one
---@field status nil|string[]    -- the lifecycle, in order, as the source's process lays it out; a status outside the list follows by name
---@field status_of nil|fun(lines: string[]): string|nil  -- pure: a document's status read from its text, for a source whose index carries none; known once the text is cached
---@field document nil|fun(model: rfc.SourceModel): rfc.Document  -- the Markdown projection, for a source whose model kind no shared format draws

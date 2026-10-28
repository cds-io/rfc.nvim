-- Completion over cached indexes and exported tags.
local config = require("rfc.config")
local store = require("rfc.store")
local sources = require("rfc.sources")
local fp = require("cds.fp")
local session = require("rfc.app.session")
local ensure_setup, enabled = session.ensure_setup, session.enabled
local label = require("rfc.app.names").label
local index_of = require("rfc.app.entries").index_of
local M = {}

--- What a command can complete to, from what is on disk: every entry of
--- each given source's cached index (fresh or stale; completion cannot wait
--- on the network), parsed once per version of the file, the word
--- `subjects` for a source that has them, and every tag of those sources'
--- cached documents.
---@param from rfc.Source[]
---@return string[]
function M.candidates(from)
    ensure_setup()
    local cfg = config.get()
    local out = fp.reduce(fp.filter(from, enabled), {}, function(all, source)
        local labels = index_of(source):memo("labels", function(lines)
            return fp.map(source.entries(lines), function(entry)
                return label(source, entry)
            end)
        end)
        return vim.list_extend(all, labels or {})
    end)
    local any_subjects = fp.any(from, function(source)
        return enabled(source) and source.subjects ~= nil
    end)
    if fp.any(from, function(source)
        return enabled(source) and source.status ~= nil
    end) then
        table.insert(out, "status")
    end
    if any_subjects then
        table.insert(out, "subjects")
    end
    local tags = store.doc_dir(cfg) .. "/tags"
    if vim.fn.filereadable(tags) == 1 then
        local entries = fp.map(vim.fn.readfile(tags), function(line)
            local name, file = line:match("^([^\t]+)\t([^\t]+)")
            return { name = name, file = file }
        end)
        -- a document's file tag is its file's name; a node named robots.txt
        -- ends the same way and is a tag to offer
        local offered = fp.filter(entries, function(t)
            return t.name ~= nil and t.name ~= t.file and vim.tbl_contains(from, sources.of(t.name))
        end)
        vim.list_extend(
            out,
            fp.map(offered, function(t)
                return t.name
            end)
        )
    end
    return out
end

--- The completion of a command's argument: every candidate when nothing
--- is typed, the fuzzy matches otherwise.
---@param from rfc.Source[]
---@param arglead string
---@return string[]
function M.complete(from, arglead)
    local candidates = M.candidates(from)
    if arglead == "" then
        return candidates
    end
    return vim.fn.matchfuzzy(candidates, arglead)
end

return M

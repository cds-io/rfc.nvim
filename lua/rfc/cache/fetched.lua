-- Fetched source files, with explicit stale-copy recovery.
local store = require("rfc.store")
local help = require("rfc.help.text")
local revision = require("rfc.revision")
local rules = require("rfc.cache.rules")
local disk = require("rfc.cache.disk")
local write, mtime_of, memo_of = disk.write, disk.mtime, disk.memo
local function task()
    return require("cds.task")
end

local M = {}

---@class rfc.Fetched
---@field cfg rfc.Config
---@field file string                 -- under the root: rfc-subjects.csv, rfc9110.txt
---@field produce fun(since: integer|nil): cds.Task  -- of the body as one string, of { body, modified } to stamp the file with a time, or of false when a copy since `since` is unchanged
---@field max_age integer|nil         -- seconds; nil never ages
---@field modified integer|nil        -- when the index says the thing changed; a copy older than that is produced again
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
    return rules.fresh(self:mtime(), now or os.time(), self.max_age, self.modified)
end

--- The copy on disk, fresh or stale; nil when there is none or it is a
--- placeholder.
---@return string[]|nil
function Fetched:cached()
    local snapshot = self:cached_snapshot()
    return snapshot and snapshot.lines
end

--- A stable source read with the revision of those exact lines.
---@return rfc.SourceSnapshot?, string?
function Fetched:cached_snapshot()
    local snapshot, err = revision.read(self:path())
    if snapshot and self.placeholder and self.placeholder(snapshot.lines) then
        return nil
    end
    return snapshot, err
end

--- The lines: the copy while fresh; else produced, cleaned, written and
--- answered, and when producing fails with a copy on disk, that copy with
--- a warning. The copy is read before producing: a failure may be met in
--- a fast event, where a file cannot be read. Producing is told the copy's
--- time, and may answer false (unchanged: the copy, nothing written) or a
--- record with the body and the time to stamp the file with.
---@return cds.Task
function Fetched:lines()
    return self:snapshot():map(function(snapshot)
        return snapshot.lines
    end)
end

--- Load a source snapshot. Its revision is captured with the data, before
--- waiting on other inputs, and is never reconstructed from later disk state.
---@return cds.Task -- of rfc.SourceSnapshot
function Fetched:snapshot()
    local cached = self:cached_snapshot()
    if cached and self:fresh() then
        return task().of(cached)
    end
    local since = cached and self:mtime() or nil
    return self.produce(since)
        :on_main()
        :bind_result(function(answer)
            if answer == false then
                if cached then
                    -- unchanged as of the index's date: the copy is stamped
                    -- with it, so it is fresh until the index moves again
                    if self.modified and revision.of(self:path()) == cached.revision then
                        vim.uv.fs_utime(self:path(), self.modified, self.modified)
                    end
                    return self:cached_snapshot() or cached
                end
                return nil, "nothing to produce " .. self.file .. " from"
            end
            local body, modified = answer, nil
            if type(answer) == "table" then
                body, modified = answer.body, answer.modified
            end
            local lines = help.clean(body)
            local ok, err = write(self:path(), lines)
            if ok and modified then
                -- the copy is as new as the server says and as the index
                -- dates it (a publication date runs past the Last-Modified),
                -- so it is fresh until the index moves again
                local stamp = math.max(modified, self.modified or 0)
                vim.uv.fs_utime(self:path(), stamp, stamp)
            end
            if not ok then
                return nil, err
            end
            return self:cached_snapshot()
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

--- `parse` over the copy on disk (fresh or stale), once per revision of the
--- file under `name`; nil when there is no copy.
---@param name string
---@param parse fun(lines: string[]): any
---@return any|nil
function Fetched:memo(name, parse)
    return memo_of(self:path(), name, parse)
end

---@param cfg rfc.Config
---@param spec { file: string, produce: (fun(since: integer|nil): cds.Task), max_age?: integer, modified?: integer, label: string, notify?: fun(msg: string, level: integer), placeholder?: fun(lines: string[]): boolean }
---@return rfc.Fetched
function M.fetched(cfg, spec)
    return setmetatable({
        cfg = cfg,
        file = spec.file,
        produce = spec.produce,
        max_age = spec.max_age,
        modified = spec.modified,
        label = spec.label,
        notify = spec.notify,
        placeholder = spec.placeholder,
    }, Fetched)
end

return M

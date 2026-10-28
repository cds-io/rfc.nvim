-- The progress report of a document being prepared, and the dashboard
-- that shows it above the document's window: the report is started where
-- the reader resolves a tag (or by a command whose pipeline runs before
-- its jump), keyed by source prefix in rfc.app.progress so the pipeline's
-- stages can report to it, and the dashboard opens once the preparation
-- has run `progress.show_after` milliseconds without ending.
local config = require("rfc.config")
local sources = require("rfc.sources")
local names = require("rfc.app.names")
local entries = require("rfc.app.entries")
local subjects_cache = require("rfc.app.subjects_cache")
local progress = require("rfc.app.progress")

local M = {}

local dashboard = require("cds.dashboard").new({
    filetype = "rfc-progress",
    linger = config.get().progress.linger,
})

--- The phases a document's preparation will run, from what the cache
--- holds now, so the report ends with every phase done.
---@param source rfc.Source
---@param id string|nil   -- nil for the subjects document
---@return string[]
local function plan_for(source, id)
    if not id then
        local page = subjects_cache.subjects_of(source)
        local current_page = page:current()
        return progress.plan({
            index = not current_page and not subjects_cache.subjects_fresh(source),
            subjects = not current_page or not page:model_held(),
            page = not current_page,
            build = true,
        })
    end
    local page = entries.document_of(source, id)
    return progress.plan({
        index = source.key == "shortname" and not entries.index_of(source):fresh(),
        text = not entries.raw_of(source, id):cached(),
        page = not page:current(),
        build = true,
    })
end

--- The bytes of the page's inputs on disk: the index for a subjects page,
--- the text for a document; what says the preparation is heavy before it
--- runs.
---@param source rfc.Source
---@param id string|nil
---@return integer
local function input_bytes(source, id)
    local input = id and entries.raw_of(source, id) or entries.subjects_index_of(source)
    local size = vim.fn.getfsize(input:path())
    return size > 0 and size or 0
end

--- A report for the document, and its dashboard above the window once
--- the preparation has run `show_after` milliseconds without ending; the
--- report already running for the source, when a command started one
--- before its jump.
---@param tag string
---@param win integer
---@return cds.ProgressReport|nil
function M.report_for(tag, win)
    local source = sources.of(tag)
    if not source then
        return nil
    end
    local running = progress.current(source.prefix)
    if running then
        return running
    end
    local id = names.id_of(source, tag)
    local title = id and (source.label .. " " .. id) or (source.subjects and source.subjects.title or tag)
    local plan = plan_for(source, id)
    local report = progress.start(source.prefix, title, plan)
    local settings = config.get().progress
    -- a fetch, or inputs past the size, is known heavy before it runs: the
    -- dashboard opens at once; anything else gets show_after to finish first
    local heavy = plan[1] == "reading source" or input_bytes(source, id) >= settings.at_once_bytes
    local function open()
        if not report:finished() and vim.api.nvim_win_is_valid(win) then
            dashboard:open(win, report)
        end
    end
    if heavy then
        -- on the next turn, which comes before the pipeline's first hop, and
        -- outside the read autocmd a jump may be running in
        vim.schedule(open)
    else
        vim.defer_fn(open, settings.show_after)
    end
    return report
end

--- Closes every dashboard; the spec harness calls it between cases.
function M.close_dashboards()
    dashboard:close_all()
end

--- The dashboard window above `win`, while a document is being prepared.
---@param win integer
---@return integer|nil
function M.dashboard_window(win)
    return dashboard:window(win)
end

--- The report the dashboard above `win` shows, while it is up.
---@param win integer
---@return cds.ProgressReport|nil
function M.progress_report(win)
    return dashboard:report(win)
end

return M

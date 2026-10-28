-- The progress reports of documents being prepared, by source prefix: the
-- reader starts one when it opens a document, and the pipeline's stages,
-- which know their source and not their window, report to it by prefix.
-- A stage with no report running for its prefix says nothing. A new
-- report for a prefix finishes the one before it, so a dashboard left on
-- an earlier window closes.
local progress = require("cds.progress")
local M = { reports = {} }

--- The phase names a document's preparation will run through, given what
--- the cache already holds: only the stages that will happen, so a report
--- ends with every phase done.
---@param stages { index: boolean, text: boolean, page: boolean, subjects: boolean, build: boolean }
---@return string[]
function M.plan(stages)
    local plan = {}
    if stages.index then
        table.insert(plan, "reading source")
    end
    if stages.text then
        table.insert(plan, "fetching the text")
    end
    if stages.subjects then
        table.insert(plan, "parsing metadata")
        table.insert(plan, "filing")
    end
    if stages.page then
        table.insert(plan, "writing the page")
    end
    if stages.build then
        table.insert(plan, "building the page")
    end
    table.insert(plan, "styling")
    return plan
end

--- Starts a report for the prefix, finishing one still running.
---@param prefix string
---@param title string
---@param plan string[]
---@return cds.ProgressReport
function M.start(prefix, title, plan)
    local before = M.reports[prefix]
    if before and not before:finished() then
        before:finish()
    end
    local report = progress.new({ title = title, plan = plan })
    M.reports[prefix] = report
    M.watch(report)
    return report
end

-- A tick every 50 ms while the report runs; a tick that comes 150 ms or
-- more late is a stretch the main loop was blocked for, noted on the
-- report under the phase running.
local TICK, BLOCK = 50, 150

--- Milliseconds from the high-resolution clock; vim.uv.now is the loop's
--- cached time, stale inside the very stretches this measures.
---@return integer
local function now_ms()
    return math.floor(vim.uv.hrtime() / 1e6)
end

--- Watches the main loop for the report's life and notes its blocks.
--- The ticks that queued up behind a block run after the first of them
--- closed the timer, so a tick that finds it closing does nothing.
---@param report cds.ProgressReport
---@return uv.uv_timer_t
function M.watch(report)
    local timer = assert(vim.uv.new_timer(), "a timer")
    local last = now_ms()
    timer:start(
        TICK,
        TICK,
        vim.schedule_wrap(function()
            if timer:is_closing() then
                return
            end
            local now = now_ms()
            if now - last >= BLOCK then
                report:block(now - last)
            end
            last = now
            if report:finished() then
                timer:stop()
                timer:close()
            end
        end)
    )
    return timer
end

---@param prefix string
---@return cds.ProgressReport?
function M.current(prefix)
    local report = M.reports[prefix]
    return report and not report:finished() and report or nil
end

---@param prefix string
---@param name string
---@param of? integer
function M.phase(prefix, name, of)
    local report = M.current(prefix)
    if report then
        report:begin(name, of)
    end
end

---@param prefix string
---@param n? integer
function M.tick(prefix, n)
    local report = M.current(prefix)
    if report then
        report:tick(n)
    end
end

---@param prefix string
---@param err string
function M.fail(prefix, err)
    local report = M.current(prefix)
    if report then
        report:fail(err)
    end
end

return M

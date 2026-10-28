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
---@param stages { index: boolean, text: boolean, page: boolean, subjects: boolean }
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
    return report
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

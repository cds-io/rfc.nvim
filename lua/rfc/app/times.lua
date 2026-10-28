-- The last open's timeline for a source, as a scratch buffer: what
-- :Crs times shows. The report is rfc.app.progress's, finished or not; the
-- lines are cds.progress's timeline, each phase with its length, the
-- draws, and every stretch the main loop was blocked for.
local progress = require("rfc.app.progress")
local M = {}

---@param source rfc.Source
---@return string[]|nil
function M.lines(source)
    local report = progress.reports[source.prefix]
    return report and report:timeline_lines() or nil
end

--- Shows the source's last timeline in `rfc://times/<prefix>`, reused when
--- it is there; says so when the source has not been opened yet.
---@param source rfc.Source
---@param notify fun(msg: string, level: integer)
function M.show(source, notify)
    local lines = M.lines(source)
    if not lines then
        notify(("no %s document opened yet; its times come after one"):format(source.label), vim.log.levels.WARN)
        return
    end
    local name = "rfc://times/" .. source.prefix
    local buf = vim.fn.bufnr(name)
    if buf == -1 then
        buf = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_buf_set_name(buf, name)
        vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = "nofile", "hide", false
        vim.bo[buf].filetype = "rfc-times"
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.api.nvim_win_set_buf(0, buf)
end

return M

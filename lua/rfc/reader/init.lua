-- Compose shared document presentation and navigation.
local Reader = {}
---@class rfc.ReaderDestination
---@field name string
---@field document rfc.Document
---@param deps { resolve: fun(tag: string, done: fun(destination: rfc.ReaderDestination?, err: string?)), notify: function, toc: table, attach: function? }
---@return table
function Reader.new(deps)
    local M = { image_wait = 500 }
    local navigation
    local bind = require("rfc.reader.keys")
    function M.attach(buf)
        bind(
            buf,
            navigation.follow,
            navigation.back,
            navigation.step,
            deps.toc.toggle,
            navigation.cancel,
            navigation.target
        )
    end
    local reporting = require("rfc.reader.progress")
    local presentation
    --- Resolves a tag with a progress report started for it, since both
    --- the read of an :edit and a jump come through here; a refusal ends
    --- the report with its reason.
    local function resolve(tag, done)
        local report = reporting.report_for(tag, vim.api.nvim_get_current_win())
        deps.resolve(tag, function(destination, err)
            if not destination and report then
                report:fail(err or "document not available")
            end
            done(destination, err)
        end)
    end
    presentation = require("rfc.reader.presentation")({
        resolve = resolve,
        notify = deps.notify,
        reload_toc = deps.toc.reload,
        attach = deps.attach,
        bindings = M.attach,
        headings = function(buf)
            return navigation.headings(buf)
        end,
        image_wait = function()
            return M.image_wait
        end,
    })
    navigation = require("rfc.reader.navigation")(
        presentation.model,
        presentation.fresh,
        presentation.show,
        resolve,
        deps.notify
    )
    M.read, M.reload, M.model, M.attach_window =
        presentation.read, presentation.reload, presentation.model, presentation.attach_window
    M.dashboard_window, M.progress_report = reporting.dashboard_window, reporting.progress_report
    M.report_for, M.close_dashboards = reporting.report_for, reporting.close_dashboards
    M.jump, M.back, M.follow = navigation.jump, navigation.back, navigation.follow
    M.headings, M.step, M.forget = navigation.headings, navigation.step, navigation.forget
    return M
end
return Reader

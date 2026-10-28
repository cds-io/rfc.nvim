-- Session configuration and the application Task boundary.
local config = require("rfc.config")
local store = require("rfc.store")
local help = require("rfc.help")
local lifecycle = require("rfc.status")
local M = {}

local TITLE = "rfc"

M._activity = require("cds.activity").new({ autocmd = "RfcActivity" })

--- The statusline segment: the fetches out, with their seconds.
---@return string
function M.activity()
    return M._activity:segment()
end

--- Every message goes through here: the reader's `notify` handler when set,
--- vim.notify with the title as a prefix otherwise. Safe from a fast event.
---@param msg string
---@param level? integer
function M.notify(msg, level)
    level = level or vim.log.levels.INFO
    local function deliver()
        local handler = config.get().notify
        if handler then
            handler(msg, level, { title = TITLE })
        else
            vim.notify(TITLE .. ": " .. msg, level, { title = TITLE })
        end
    end
    if vim.in_fast_event() then
        vim.schedule(deliver)
    else
        deliver()
    end
end
local configured = false
function M.setup(opts, root)
    help.set_render(store.render_version(root or M.root))
    local ok, err = store.register(config.set(opts))
    -- a session's status choices start over with its settings
    lifecycle.chosen = {}
    configured = true
    if not ok then
        M.notify(assert(err, "a refused registration carries its error"), vim.log.levels.ERROR)
    end
end

function M.ensure_setup()
    if not configured then
        M.setup()
    end
end

---@param source rfc.Source
---@return boolean
function M.enabled(source)
    return config.get().sources[source.prefix] == true
end
--- Runs a Task on the main loop, tracked in the activity segment, and hands
--- `done(value, err)` its outcome; a thrown error arrives as the err.
---@param task cds.Task
---@param label string
---@param done fun(value: any, err: any)
function M.run(task, label, done)
    local handle = task:on_main():run()
    M._activity:track("fetch", label, handle)
    handle:on_complete(function(terr, value, err)
        vim.schedule(function()
            done(value, terr and tostring(terr) or err)
        end)
    end)
end

return M

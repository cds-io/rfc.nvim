-- The one module that spawns processes. Everything runs by argv (never a
-- shell), anything secret travels on stdin, and a non-zero exit is data the
-- caller reads from `code`; the only failure path is a process that never
-- started.
local async = require("cds.async")

local M = {}

---@class cds.proc.Result
---@field code integer
---@field signal integer
---@field stdout string
---@field stderr string
---@field timed_out boolean   -- `timeout` elapsed and the process was killed

---@class cds.proc.Opts
---@field stdin string?
---@field timeout integer?    -- milliseconds
---@field env table<string, string>?

--- Spawns `argv` and awaits it. Specs replace this to replay recorded output.
---
--- vim.system calls on_exit in a fast event context, where vim.env, vim.fn and
--- most of the API raise E5560. The callback is scheduled so the awaiting
--- task resumes on the main loop and its caller never has to care.
---@param argv string[]
---@param opts cds.proc.Opts
---@return vim.SystemCompleted
function M.runner(argv, opts)
  local sys_opts = { stdin = opts.stdin, timeout = opts.timeout, env = opts.env, text = true }
  return async.await(3, function(cmd, o, on_exit)
    return vim.system(cmd, o, vim.schedule_wrap(on_exit))
  end, argv, sys_opts)
end

---@param argv string[]
---@param opts? cds.proc.Opts
---@return cds.proc.Result? result
---@return string? err        -- when the process could not be spawned
function M.run(argv, opts)
  opts = opts or {}
  local ok, obj = pcall(M.runner, argv, opts)
  if not ok then
    return nil, ("%s: %s"):format(argv[1], tostring(obj):gsub("^.-:%d+: ", ""))
  end
  return {
    code = obj.code,
    signal = obj.signal,
    stdout = obj.stdout or "",
    stderr = obj.stderr or "",
    timed_out = obj.code == 124 and obj.signal == 15,
  }
end

return M

-- A lazy asynchronous result over vim.async. Composition passes one value and
-- one error; nil and false are valid successes. Only run starts effects.
local async = require("cds.async")
---@class cds.Task
---@field private evaluate fun(): any, any
local Task = {}
Task.__index = Task

--- fn may yield and returns (value, err). Exceptions become errors at run.
---@param fn fun(): any, any
---@return cds.Task
function Task.new(fn)
  return setmetatable({ evaluate = fn }, Task)
end

---@param value any
---@return cds.Task
function Task.of(value)
  return Task.new(function()
    return value
  end)
end

---@param err any
---@return cds.Task
function Task.fail(err)
  assert(err ~= nil, "a task error must not be nil")
  return Task.new(function()
    return nil, err
  end)
end

---@param fn fun(value: any): cds.Task
---@return cds.Task
function Task:bind(fn)
  return Task.new(function()
    local value, err = self.evaluate()
    if err ~= nil then
      return nil, err
    end
    return fn(value).evaluate()
  end)
end

---@param fn fun(value: any): any
---@return cds.Task
function Task:map(fn)
  return self:bind(function(value)
    return Task.of(fn(value))
  end)
end

--- Run fn for its effect and pass the value on unchanged. A step that
--- records or reports what flowed through it, without a map that has to
--- remember to return its input.
---@param fn fun(value: any)
---@return cds.Task
function Task:tap(fn)
  return self:map(function(value)
    fn(value)
    return value
  end)
end

--- Pass the value on when pred holds for it; otherwise fail. `reason` is the
--- error, or a function of the value that builds it, for the message that
--- wants to quote what was wrong.
---@param pred fun(value: any): boolean
---@param reason any|fun(value: any): any
---@return cds.Task
function Task:ensure(pred, reason)
  return self:bind(function(value)
    if pred(value) then
      return Task.of(value)
    end
    return Task.fail(type(reason) == "function" and reason(value) or reason)
  end)
end

-- Recovery also catches exceptions, inside the child rather than its awaiter:
-- an uncaught vim.async child failure can cancel its siblings.
---@param fn fun(err: any): cds.Task
---@return cds.Task
function Task:recover(fn)
  return Task.new(function()
    local ok, value, err = pcall(self.evaluate)
    if not ok then
      err = value
    end
    if err ~= nil then
      return fn(err).evaluate()
    end
    return value
  end)
end

--- Resume composition on Neovim's main loop after a fast-event producer.
---@return cds.Task
function Task:on_main()
  return Task.new(function()
    local value, err = self.evaluate()
    if vim.in_fast_event() then
      async.await(1, vim.schedule)
    end
    return value, err
  end)
end

--- Evaluate while holding an existing semaphore, shared across the batch.
---@return cds.Task
function Task:limited(semaphore)
  return Task.new(function()
    return semaphore:with(self.evaluate)
  end)
end

--- Time a successful result. limited(...):timed() includes queue time;
--- timed():limited(...) measures only the time after acquiring the permit.
--- Errors retain their original error channel.
---@param now? fun(): number Nanoseconds; injectable for deterministic checks.
---@return cds.Task
function Task:timed(now)
  now = now or vim.uv.hrtime
  return Task.new(function()
    local started = now()
    local value, err = self.evaluate()
    if err ~= nil then
      return nil, err
    end
    return { value = value, ms = math.floor((now() - started) / 1e6) }
  end)
end

--- Starts a fresh run and returns the native handle for activity/on_complete.
---@return vim.async.Task
function Task:run()
  return async.run(function()
    local ok, value, err = pcall(self.evaluate)
    if not ok then
      return nil, value
    end
    return value, err
  end)
end

--- Starts all tasks and joins every run, even on error: remote writes cannot
--- be rolled back by cancelling their siblings. Results retain nil slots via n.
--- Returns the first error in input order only after all runs have settled.
---@param tasks cds.Task[]
---@return cds.Task
function Task.all(tasks)
  local inputs = vim.list_extend({}, tasks)
  return Task.new(function()
    local runs, values, first_error = {}, { n = #inputs }, nil
    for i, task in ipairs(inputs) do
      runs[i] = task:run()
    end
    for i, run in ipairs(runs) do
      local value, err = async.await(run)
      values[i] = value
      if first_error == nil and err ~= nil then
        first_error = err
      end
    end
    if first_error ~= nil then
      return nil, first_error
    end
    return values
  end)
end

return Task

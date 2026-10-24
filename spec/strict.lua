-- The busted helper, loaded before every spec in both tiers: the cds modules
-- rfc.needs declares, behind proxies that refuse any other name, so a spec
-- that reaches an undeclared cds function fails and the declaration stays
-- what the code uses. The specs have two uses of their own, as test tooling
-- rather than as the plugin: async.await to resume a Task in a fast event,
-- and images._use to choose the image backend under test. They are allowed
-- here, beside the plugin's declaration rather than in it.
local declared = require("rfc.needs")
local extras = { async = { "await" }, images = { "_use" } }
local capabilities = {}
for name, fns in pairs(declared) do
    capabilities[name] = { unpack(fns) }
end
for name, fns in pairs(extras) do
    capabilities[name] = capabilities[name] or {}
    for _, fn in ipairs(fns) do
        table.insert(capabilities[name], fn)
    end
end
require("cds.needs").strict("rfc.nvim", capabilities)

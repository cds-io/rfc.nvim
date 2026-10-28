-- Source-specific projections onto the shared document contract.
local M = {}
M.from_help = require("rfc.document.help")
local render = {
    html = require("rfc.document.report"),
    rfc = require("rfc.document.rfc"),
    proposal = require("rfc.document.proposal"),
    subjects = require("rfc.document.subjects"),
}
---@param model rfc.SourceModel
---@return rfc.Document
function M.from_model(model)
    return assert(render[model.kind], "unknown source model")(model)
end

---@param id string
---@param lines string[]
---@param url string
---@return rfc.Document
function M.report(id, lines, url)
    return M.from_model(require("rfc.help_w3c").model(id, lines, url))
end

return M

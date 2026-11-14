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

return M

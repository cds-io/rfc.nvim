-- The shared formats' projections onto the document contract, by model kind;
-- a source whose kind no format draws carries its own (rfc.Source.document).
local M = {}
M.from_help = require("rfc.document.help")
local render = {
    html = require("rfc.document.report"),
    proposal = require("rfc.document.proposal"),
    subjects = require("rfc.document.subjects"),
}
---@param model rfc.SourceModel
---@return rfc.Document
function M.from_model(model)
    return assert(render[model.kind], "unknown source model")(model)
end

return M

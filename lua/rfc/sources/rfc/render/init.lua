---@class rfc.RfcModel
---@field kind "rfc"
---@field name string
---@field title string
---@field blocks rfc.sources.rfc.reader.Block[]
---@field tag_of table<rfc.sources.rfc.reader.Block, string>
---@field context rfc.help.Context

-- The RFC as a Vim help document. render is total: whatever the text, it
-- answers a document and the tags that name its headings, so a reader can
-- `:help rfc9110-3.1`, follow |links| with CTRL-] and come back with CTRL-T.
-- Nothing here touches the editor; the store writes the document and the
-- tags file, and `:help` does the rest.
local model = require("rfc.sources.rfc.render.model")
local M = {}
M.target, M.model = model.target, model.model
M.render_model = require("rfc.sources.rfc.render.render").render_model
M.document = require("rfc.sources.rfc.render.document")

---@param rfc_num string
---@param lines string[]
---@return rfc.HelpDoc
function M.render(rfc_num, lines)
    return M.render_model(M.model(rfc_num, lines))
end

return M

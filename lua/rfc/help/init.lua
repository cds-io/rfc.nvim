---@alias rfc.SourceModel rfc.RfcModel|rfc.ProposalModel|rfc.SubjectsModel|rfc.ReportModel

---@class rfc.RfcModel
---@field kind "rfc"
---@field name string
---@field title string
---@field blocks rfc.source.rfc.Block[]
---@field tag_of table<rfc.source.rfc.Block, string>
---@field context rfc.help.Context

-- The RFC as a Vim help document. render is total: whatever the text, it
-- answers a document and the tags that name its headings, so a reader can
-- `:help rfc9110-3.1`, follow |links| with CTRL-] and come back with CTRL-T.
-- Nothing here touches the editor; the store writes the document and the
-- tags file, and `:help` does the rest.

---@class rfc.HelpTag
---@field name string
---@field line integer   -- the line of the rendered document the tag sits on

---@class rfc.HelpDoc
---@field lines string[]
---@field tags rfc.HelpTag[]
---@field model? rfc.SourceModel -- immutable source plan shared with the Markdown renderer

local M = require("rfc.help.version")
local tags = require("rfc.help.tags")
local text = require("rfc.help.text")
local model = require("rfc.help.model")
M.slug, M.tag, M.ref_tag = tags.slug, tags.tag, tags.ref_tag
M.TAG, M.SECTION = tags.TAG, tags.SECTION
M.tags_in, M.section_tag, M.row_tag, M.tags_file = tags.tags_in, tags.section_tag, tags.row_tag, tags.tags_file
M.title, M.clean, M.with_tag = text.title, text.clean, text.with_tag
M.target, M.model = model.target, model.model
M.render_model = require("rfc.help.render").render_model

---@param rfc_num string
---@param lines string[]
---@return rfc.HelpDoc
function M.render(rfc_num, lines)
    return M.render_model(M.model(rfc_num, lines))
end

return M

---@alias rfc.SourceModel rfc.RfcModel|rfc.ProposalModel|rfc.SubjectsModel|rfc.ReportModel

-- The help projection every render writes through: the render version and
-- footer, the tags and their shapes, and the text helpers. Each source's
-- render (rfc.help_rfc, rfc.help_eip, rfc.format.report and the rest) builds
-- its document over these.

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
M.slug, M.tag, M.ref_tag = tags.slug, tags.tag, tags.ref_tag
M.tags_in, M.section_tag, M.row_tag, M.tags_file = tags.tags_in, tags.section_tag, tags.row_tag, tags.tags_file
M.title, M.clean, M.with_tag = text.title, text.clean, text.with_tag

return M

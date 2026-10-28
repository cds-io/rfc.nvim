---@class rfc.ProposalPlan
---@field tags table<rfc.ProposalBlock, string>
---@field texts table<rfc.ProposalBlock, string>
---@field top integer

---@class rfc.ProposalModel
---@field kind "proposal"
---@field name string
---@field title string
---@field id string
---@field fields table<string, string>
---@field blocks rfc.ProposalBlock[]
---@field aliases string[]
---@field header rfc.Inline[]
---@field inlines table<string, rfc.Inline>
---@field body rfc.ProposalPlan

-- The proposal render, over a declaration of what a source's proposals
-- look like: how the text reads into its fields and blocks, which fields
-- make the header and which name other proposals, how the text names a
-- proposal. The document is the same shape for every source: a title line
-- with the file tags, a header line, the rows the fields give, then the
-- body as one fold over the blocks with a contents block of links first.
-- A heading gets a tag of the file tag and its slug (numbered when a title
-- repeats), a fence becomes a help code block, a table aligned columns,
-- the notes a numbered list, and a line goes through the link pass.
-- Nothing here touches the editor.
---@class rfc.ProposalRow
---@field key string                           -- the frontmatter field
---@field as "text"|"links"|fun(value: string): string[]  -- as written; the numbers as |prefixN| links; a list, joined with commas

---@class rfc.ProposalSpec
---@field prefix string                                -- the tag prefix: eip, bip, simd
---@field label fun(fields: table<string, string>): string   -- the title's fallback: "BIP 32" is label .. " " .. id
---@field number fun(fields: table<string, string>, id: string): string  -- the header's first cell: EIP-1559, SIMD-0064
---@field read fun(lines: string[]): table<string, string>, rfc.ProposalBlock[]  -- the fields and the body's blocks
---@field header string[]                              -- the fields the header line carries, in order
---@field rows (rfc.ProposalRow|fun(fields: table<string, string>, id: string): rfc.Inline|string|nil)[]  -- lines after the header, each when its field is set
---@field tags nil|fun(fields: table<string, string>, id: string): string[]  -- other names the file is tagged by: erc20 for an ERC
---@field mentions fun(line: string): rfc.source.Mention[]    -- what the text names
local M = {}
local inline = require("rfc.proposal.inline")
local body = require("rfc.proposal.body")
M.format, M.inline, M.links, M.row, M.linker = inline.format, inline.inline, inline.links, inline.row, inline.linker
M.layout, M.plan_body, M.body = body.layout, body.plan_body, body.body
M.model = require("rfc.proposal.model").model
M.render_model = require("rfc.proposal.render").render_model

---@param spec rfc.ProposalSpec
---@param id string
---@param lines string[]
---@return rfc.HelpDoc
function M.render(spec, id, lines)
    return M.render_model(M.model(spec, id, lines))
end

return M

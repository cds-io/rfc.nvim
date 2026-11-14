-- Reads what is Ethereum's in an improvement proposal: `mentions` finds the
-- EIPs and ERCs a line names, `requires` the numbers a `requires:` field
-- names, and `listing` reads eips.ethereum.org/all (or the ERC site's page)
-- as entries. The Markdown itself is rfc.format.proposal.markdown's. Every
-- function takes lines and answers tables, so the specs run under plain
-- busted.

---@class rfc.source.eip
local M = {}

---@class rfc.source.eip.Mention
---@field kind "eip"|"erc"
---@field first integer   -- byte range of the text a link would replace
---@field last integer
---@field id string

---@class rfc.source.eip.Entry
---@field id string
---@field title string
---@field status string   -- the listing's section: "Final", "Draft", ...
---@field category string -- the page's title: "Core", "ERC", "All"; "" before any

local inline = require("rfc.source.eip.inline")
M.mentions, M.requires, M.listing = inline.mentions, inline.requires, inline.listing

return M

-- The Solana proposals' directory and files, as Tasks. A spec replaces the functions
-- below with Tasks of fixture text.
local fetch = require("rfc.fetch")

local M = {}

local SIMD_REPO = "solana-foundation/solana-improvement-documents"

--- The Solana proposals directory as the GitHub contents API lists it,
--- which is the index: the file names carry the slugs the numbers alone
--- do not give.
---@return cds.Task
function M.simd_listing()
    return fetch.text("https://api.github.com/repos/" .. SIMD_REPO .. "/contents/proposals", "the SIMD index")
end

--- A Solana proposal's markdown by its file name in the directory.
---@param file string  -- 0064-transaction-receipt.md
---@param id string    -- the number, for the message
---@return cds.Task
function M.simd(file, id)
    return fetch.text(fetch.github_raw .. SIMD_REPO .. "/main/proposals/" .. file, "SIMD " .. id)
end

return M

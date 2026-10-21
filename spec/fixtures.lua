-- The RFC texts the plugin's specs read: the same five RFCs and index
-- excerpt the cds.rfc spec uses in ../cds (fetched from the RFC Editor,
-- form feeds and the byte-order mark removed, as a fetched text is stored).
-- Resolved from this file's own directory so a spec runs from any working
-- directory (the nlua run starts busted twice).
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."

local M = {
    rfc791 = "rfc791.txt",
    rfc1945 = "rfc1945.txt",
    rfc2616 = "rfc2616.txt",
    rfc3986 = "rfc3986.txt",
    rfc9110 = "rfc9110.txt",
    rfc_index = "rfc-index.txt",
    -- Ethereum proposals (CC0) and excerpts of the two listing pages, the
    -- same files the cds.eip spec reads in ../cds
    eip1 = "eip-1.md",
    eip1559 = "eip-1559.md",
    erc20 = "erc-20.md",
    eip20_moved = "eip-20-moved.md",
    erc1123 = "erc-1123.md",
    eips_all = "eips-all.html",
    ercs_all = "ercs-all.html",
    bip32 = "bip-0032.mediawiki",
    bip22 = "bip-0022.mediawiki",
    bip341 = "bip-0341.mediawiki",
    bip3 = "bip-0003.md",
    bips_readme = "bips-README.mediawiki",
    simd64 = "simd-0064-transaction-receipt.md",
    simd1 = "simd-0001-simd-process.md",
    simd_related = "simd-0268-raise-cpi-nesting-limit.md",
    simd_listing = "simd-proposals.json",
}

---@param name string
---@return string[]
function M.read(name)
    local lines = {}
    for line in io.lines(here .. "/fixtures/" .. name) do
        table.insert(lines, line)
    end
    return lines
end

return M

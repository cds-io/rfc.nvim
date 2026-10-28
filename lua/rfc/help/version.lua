-- Session render fingerprint, shared by help projections.
local M = {}
M.MODELINE = " vim:tw=78:ts=8:ft=help:norl:"
-- The render's version, written as the document's last line. A cached
-- document whose line names another version is rendered again from the
-- stored text, so a changed render reaches what is already on disk. The
-- rim sets it to a fingerprint of the plugin's code (store.render_version)
-- at setup, so no hand keeps count; alone, the core writes "dev".
M.RENDER = "dev"
M.FOOTER = " rfc.nvim render " .. M.RENDER

--- Sets the render version and the footer that writes it.
---@param version string
function M.set_render(version)
    M.RENDER = version
    M.FOOTER = " rfc.nvim render " .. version
end

--- The render version a document's last line names, "" when it names none.
---@param lines string[]
---@return string
function M.render_of(lines)
    local last = lines[#lines] or ""
    return last:match("^ rfc%.nvim render (%S+)$") or ""
end

return M

-- The RFC Editor's text, index and subject tags, as Tasks. A spec replaces the functions
-- below with Tasks of fixture text.
local fetch = require("rfc.fetch")

local M = {}

M.rfc_editor = "https://www.rfc-editor.org/"

---@param rfc_num string
---@return cds.Task  -- of the text as one string
function M.rfc(rfc_num)
    return fetch.text(M.rfc_editor .. "rfc/rfc" .. rfc_num .. ".txt", "RFC " .. rfc_num)
end

---@return cds.Task  -- of the index text as one string
function M.index()
    return fetch.text(M.rfc_editor .. "rfc-index.txt", "the RFC index")
end

M.subject_tags = "https://rfc-editor.github.io/rfc-subject-tags/rfc-tags.csv"

--- The RFC Editor's subject tags, the CSV their pipeline publishes daily.
---@return cds.Task  -- of the CSV as one string
function M.subjects()
    return fetch.text(M.subject_tags, "the RFC subjects")
end

return M

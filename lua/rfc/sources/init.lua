-- The sources a document can come from. Each is one record the rims read
-- without knowing which they hold: where its text and its index come from,
-- how its index reads, and how its text renders. The RFC Editor is one;
-- Ethereum's proposals are another, over two repositories that share one
-- number space (ERC-20 is EIP-20), so the reader never has to say which;
-- Bitcoin's proposals are the third, Solana's the fourth, the W3C's reports
-- the fifth and the Congressional Research Service's the sixth.
local fp = require("cds.fp")
local M = {
    rfc = require("rfc.sources.rfc"),
    eip = require("rfc.sources.eip"),
    bip = require("rfc.sources.bip"),
    simd = require("rfc.sources.simd"),
    w3c = require("rfc.sources.w3c"),
    crs = require("rfc.sources.crs"),
}
M.all = { M.rfc, M.eip, M.bip, M.simd, M.w3c, M.crs }

--- The source a tag belongs to, by its prefix or one of the aliases, or
--- nil: a document's tag (eip1559-abstract) or a subjects tag
--- (eip-subjects, eip-subjects-core).
---@param tag string
---@return rfc.Source|nil
function M.of(tag)
    -- the dashed form first, a prefix ending in a letter (w3c, rfc): the
    -- number form would read "w" from "w3c-…", and the dashed form must
    -- not read "rfc9110" from "rfc9110-3.1"
    local prefix = tag:match("^(%l[%l%d]-%l)%-") or tag:match("^(%l+)%d")
    if not prefix then
        return nil
    end
    return (
        fp.find(M.all, function(source)
            return source.prefix == prefix
                or fp.any(source.aliases, function(alias)
                    return alias == prefix
                end)
        end)
    )
end

return M

---@class rfc.Entry
---@field id string
---@field label string      -- what the picker shows after the tag
---@field text boolean      -- whether the source has a text to render (an RFC published as PDF only has none)
---@field date string|nil   -- YYYY-MM-DD, when the index dates the document (a W3C report's publication)
---@field file string|nil   -- the document's file as the index spells it (a proposal's path, a report's URL), for a source that is `located`
---@field status string|nil -- where the document stands in its lifecycle (Draft, Final), for a source with `status`

---@class rfc.Subjects
---@field index_file string|nil   -- the cache file the subjects index is stored as; the source's own index file when the index carries the subjects
---@field index nil|fun(): cds.Task   -- of the index text as one string
---@field entries nil|fun(lines: string[]): rfc.source.subjects.Entry[]|nil, string|nil  -- pure: the subjects from the index
---@field texts boolean|nil       -- the subjects come from the documents' own texts, every one the index names
---@field entry nil|fun(id: string, lines: string[]): rfc.source.subjects.Entry  -- pure: a document's subjects from its text
---@field title string            -- the document's title: RFCs by subject
---@field about string            -- the line naming the data
---@field roots string[]|nil      -- the roots first, in this order; the rest follow by name

---@class rfc.Source
---@field prefix string     -- the tag prefix: rfc, eip
---@field key "number"|"shortname"|nil  -- what names a document: a number (rfc9110) unless said; a shortname joins with a dash (w3c-wcag22)
---@field aliases string[]  -- other prefixes whose tags this source answers: erc for eip
---@field label string      -- how a message names it: RFC, EIP
---@field raw_ext string    -- the extension the fetched text is stored under
---@field index_file string -- the cache file the index is stored as
---@field fetch fun(id: string, file?: string, since?: integer): cds.Task  -- of the text as one string; `file` is the entry's, for a located source; `since` the copy's time, for a source that asks conditionally
---@field located boolean|nil  -- the index names each document's file (its entries carry `file`), so a fetch goes through the index the rim keeps
---@field index fun(): cds.Task                    -- of the index text as one string
---@field entries fun(lines: string[]): rfc.Entry[]  -- pure
---@field prepare nil|fun(id: string, lines: string[], file?: string): rfc.SourceModel -- pure source plan
---@field render_model fun(model: rfc.SourceModel): rfc.HelpDoc
---@field render fun(id: string, lines: string[], file?: string): rfc.HelpDoc  -- pure, total; `file` is the entry's, for a located source
---@field placeholder nil|fun(lines: string[]): boolean  -- pure: whether a stored text stands in for the document rather than being it
---@field subjects nil|rfc.Subjects   -- the source's taxonomy, for a source that has one
---@field status nil|string[]    -- the lifecycle, in order, as the source's process lays it out; a status outside the list follows by name
---@field status_of nil|fun(lines: string[]): string|nil  -- pure: a document's status read from its text, for a source whose index carries none; known once the text is cached

local fetch = require("rfc.fetch")
local help_w3c = require("rfc.help_w3c")
local w3c = require("rfc.source.w3c")
local subjects = require("rfc.source.subjects")
local fp = require("cds.fp")

local M = {}

--- A report's picker label: its title, with the maturity when the index
--- gives one.
---@param e rfc.source.w3c.Entry
---@return string
local function report_label(e)
    return e.maturity ~= "" and (e.title .. " (" .. e.maturity .. ")") or e.title
end

--- The W3C's technical reports, by shortname: the TR page is the index,
--- a report is fetched at the URL the page spells (89 shortnames carry
--- uppercase letters, and the lowercased URL only redirects), asked
--- conditionally when a copy is on disk, and rendered through rfc.source.html.
---@type rfc.Source
M.w3c = {
    prefix = "w3c",
    aliases = {},
    label = "W3C",
    key = "shortname",
    raw_ext = "html",
    index_file = "w3c-index.html",
    located = true,
    fetch = function(id, url, since)
        return fetch.w3c(url, id, since)
    end,
    index = function()
        return fetch.listing("https://www.w3.org/TR/", "the W3C index")
    end,
    entries = function(lines)
        return fp.map(w3c.index(lines), function(e)
            return {
                id = e.id,
                label = report_label(e),
                text = true,
                date = e.date,
                file = e.url,
                status = e.maturity ~= "" and e.maturity or nil,
            }
        end)
    end,
    render = help_w3c.render,
    render_model = help_w3c.render_model,
    -- the maturities as the TR page names them: the Recommendation track,
    -- then the Note track, the Registry track and Statements
    status = {
        "Draft Standard",
        "Candidate Standard",
        "Standard",
        "Draft Note",
        "Note",
        "Draft Registry",
        "Candidate Registry",
        "Registry",
        "Statement",
    },
    -- three roots: the maturity, the tags, the groups by their short names
    -- (WG, IG), since 133 of 135 end in Working Group or Interest Group
    subjects = {
        index_file = "w3c-index.html",
        index = function()
            return fetch.listing("https://www.w3.org/TR/", "the W3C index")
        end,
        entries = function(lines)
            return fp.map(w3c.index(lines), function(e)
                local paths = e.maturity ~= "" and { { "Maturity", e.maturity } } or {}
                vim.list_extend(
                    paths,
                    fp.map(e.tags, function(tag)
                        return { "Tags", tag }
                    end)
                )
                vim.list_extend(
                    paths,
                    fp.map(e.groups, function(group)
                        return { "Deliverers", w3c.short_group(group) }
                    end)
                )
                return subjects.entry(e.id, report_label(e), paths)
            end)
        end,
        title = "W3C reports by subject",
        about = "From www.w3.org/TR, each report's maturity, tags and working group.",
        roots = { "Maturity", "Tags", "Deliverers" },
    },
}

M.w3c.prepare = help_w3c.model
return M.w3c

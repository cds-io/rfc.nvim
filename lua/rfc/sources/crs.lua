local fetch = require("rfc.fetch")
local help_w3c = require("rfc.help_w3c")
local model = require("rfc.help.crs.model")
local crs = require("rfc.source.crs")
local w3c = require("rfc.source.w3c")
local subjects = require("rfc.source.subjects")
local Task = require("cds.task")
local fp = require("cds.fp")

local M = {}

-- The site's topic pages, which together list every report it mirrors
-- (23,582 of 23,590 on 2026-10-28; the eight missing are malformed rows of
-- its CSV). The set is stable, so it lives here; a topic the site adds is
-- one slug more. "crs-insights" names a product line, not a subject, so
-- the subjects file its reports under Type alone.
-- stylua: ignore
local TOPICS = {
    "african-affairs", "aging-policy", "agricultural-policy", "american-law", "appropriations",
    "asian-affairs", "constitutional-questions", "crime-policy", "crs-insights", "domestic-social-policy",
    "economic-policy", "education-policy", "energy-policy", "environmental-policy", "european-affairs",
    "foreign-affairs", "health-policy", "immigration-policy", "indian-affairs-policy", "industry-and-trade",
    "intelligence-and-national-security", "internet-and-telecommunications-policy", "latin-american-affairs",
    "legislative-process", "middle-eastern-affairs", "national-defense",
    "russian-central-asian-and-eurasian-affairs", "science-and-technology-policy", "south-asian-affairs",
    "transportation-policy", "uncategorized", "veterans-policy",
}
local NOT_A_TOPIC = { ["CRS Insights"] = true }

--- The 32 topic pages, one after the other, each behind its marker, as
--- one text: the index and the taxonomy in one cached file.
---@return cds.Task
local function index()
    local pages = fp.map(TOPICS, function(slug)
        return fetch
            .listing(crs.BASE .. "topics/" .. slug .. ".html", "the CRS " .. slug .. " topic")
            :map(function(text)
                return crs.marker(slug) .. "\n" .. text
            end)
    end)
    return Task.all(pages):map(function(texts)
        return table.concat(texts, "\n")
    end)
end

--- A report's picker label: its title and the year of its newest version.
---@param e rfc.source.crs.Entry
---@return string
local function label(e)
    return e.title .. " (" .. e.latest:sub(1, 4) .. ")"
end

--- A report's text: its JSON record names the newest version's HTML file
--- on the mirror, which is fetched and stored behind the fact line, the
--- copy stamped with the version's date so the index's latest date moving
--- past it is what fetches again. A version with no HTML rendering is
--- refused with the PDF named.
---@param id string   -- the lowercased number
---@return cds.Task
local function fetch_report(id)
    return fetch.crs_json(id:upper()):bind(function(text)
        local v, err = crs.version(text)
        if not v then
            return Task.fail(("CRS %s: %s"):format(id:upper(), err))
        end
        if not v.html then
            return Task.fail(
                ("CRS %s has no HTML rendering; the PDF is %s"):format(
                    v.number,
                    v.pdf or (crs.BASE .. (v.mirror or ""))
                )
            )
        end
        return fetch.crs_html(v.html, v.number):map(function(html)
            return { body = crs.facts(v) .. "\n" .. html, modified = w3c.date_time(v.date) }
        end)
    end)
end

--- The Congressional Research Service's reports, from EveryCRSReport.com, by
--- report number: the 32 topic pages are the index, a report is fetched
--- through its JSON record to the mirror's HTML, normalized by
--- rfc.source.crs and rendered as a W3C report is.
---@type rfc.Source
M.crs = {
    prefix = "crs",
    aliases = {},
    label = "CRS",
    key = "shortname",
    raw_ext = "html",
    index_file = "crs-topics.html",
    fetch = fetch_report,
    index = index,
    entries = function(lines)
        return fp.map(crs.index(lines), function(e)
            return { id = e.id, label = label(e), text = true, date = e.latest }
        end)
    end,
    render = function(id, lines)
        return help_w3c.render_model(model.model(id, lines))
    end,
    render_model = help_w3c.render_model,
    prepare = model.model,
    -- two roots: the topics a report is listed under, and its product type
    -- read from its number
    subjects = {
        index_file = "crs-topics.html",
        index = index,
        entries = function(lines)
            return fp.map(crs.index(lines), function(e)
                local paths = fp.filter_map(e.topics, function(name)
                    return not NOT_A_TOPIC[name] and { "Topics", name } or nil
                end)
                table.insert(paths, { "Type", crs.kind(e.number) })
                return subjects.entry(e.id, label(e), paths)
            end)
        end,
        title = "CRS reports by topic",
        about = "From EveryCRSReport.com, the site's topic pages; the type is read from the report number.",
        roots = { "Topics", "Type" },
    },
}

return M.crs

-- Reads the US Congressional Research Service's reports as EveryCRSReport.com
-- mirrors them. The reading goes in four pieces, one module each:
-- `rfc.sources.crs.reader.topics` reads the joined topic pages into the index and
-- the taxonomy, `rfc.sources.crs.reader.version` reads a report's JSON record for
-- its newest version and the links back to the original, `rfc.sources.crs.reader.facts`
-- writes them into the stored text and reads them back, `rfc.sources.crs.reader.mentions`
-- finds the reports a line cites, and `rfc.sources.crs.reader.normalize` rewrites a
-- report's HTML into the shape the shared readers render well. This file is
-- the surface.
local topics = require("rfc.sources.crs.reader.topics")
local version = require("rfc.sources.crs.reader.version")
local facts = require("rfc.sources.crs.reader.facts")
local mentions = require("rfc.sources.crs.reader.mentions")
local normalize = require("rfc.sources.crs.reader.normalize")

return {
    BASE = "https://www.everycrsreport.com/",
    marker = topics.marker,
    topics = topics.topics,
    index = topics.index,
    kind = topics.kind,
    date = topics.date,
    long_date = topics.long_date,
    version = version.version,
    facts = facts.facts,
    read_facts = facts.read_facts,
    mentions = mentions.mentions,
    normalize = normalize.normalize,
}

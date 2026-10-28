-- Reads the Congressional Research Service's reports as EveryCRSReport.com
-- mirrors them. The reading goes in four pieces, one module each:
-- `rfc.source.crs.topics` reads the joined topic pages into the index and
-- the taxonomy, `rfc.source.crs.version` reads a report's JSON record for
-- its newest version and the links back to the original, `rfc.source.crs.mentions`
-- finds the reports a line cites, and `rfc.source.crs.normalize` rewrites a
-- report's HTML into the shape the shared readers render well. This file is
-- the surface.
local topics = require("rfc.source.crs.topics")

return {
    BASE = "https://www.everycrsreport.com/",
    marker = topics.marker,
    topics = topics.topics,
    index = topics.index,
    kind = topics.kind,
    date = topics.date,
    long_date = topics.long_date,
}

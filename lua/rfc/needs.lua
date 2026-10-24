-- What the plugin needs from cds-lua, by module and name. lazy.lua names the
-- dependency; this names what has to be there for
-- it to run, whichever commit is installed, since one cds-lua serves every
-- plugin of the family and cds-lua grows by addition. cds.needs checks it at
-- startup, and the spec harness holds the plugin to the same list. A Task's
-- methods are reached through its instances, not this table, so only the
-- constructors are named.
---@type table<string, string[]>
return {
    activity = { "new" },
    async = { "semaphore" },
    bip = { "blocks", "format", "index", "mentions", "preamble" },
    eip = { "blocks", "frontmatter", "listing", "mentions" },
    fp = { "all", "any", "each", "filter", "filter_map", "find", "find_map", "map", "reduce", "set", "unique" },
    html = { "blocks", "head" },
    http = { "request", "status" },
    images = { "available", "clear_all", "place" },
    redraw = { "windows" },
    result = { "bind", "traverse" },
    rfc = { "blocks", "cited_rfc", "index" },
    simd = { "index", "list", "mentions", "number" },
    subjects = { "entry", "rfc", "tree" },
    task = { "all", "fail", "new", "of" },
    w3c = { "date_time", "http_time", "index", "parse_http_time", "short_group" },
}

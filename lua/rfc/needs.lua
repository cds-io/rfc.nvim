-- What the plugin needs from the cds libraries, by module and name. lazy.lua names the
-- dependency; this names what has to be there for
-- it to run, whichever commit is installed, since one copy of each serves every
-- plugin of the family and the libraries grow by addition. cds.needs checks it at
-- startup, and the spec harness holds the plugin to the same list. A Task's
-- methods are reached through its instances, not this table, so only the
-- constructors are named.
---@type table<string, string[]>
return {
    document = { "unique_names", "target", "rendered", "new", "anchor", "link_at" },
    document_view = { "new" },
    window = { "close_or" },
    html = { "document", "escape" },
    navigator = { "new" },
    vellum = { "render", "restyle", "forget", "generation" },
    activity = { "new" },
    companion = { "new" },
    dashboard = { "new" },
    progress = { "new" },
    command = { "register" },
    persist = { "write_lines" },
    async = { "semaphore" },
    fp = {
        "all",
        "any",
        "each",
        "filter",
        "filter_map",
        "find",
        "find_map",
        "map",
        "memoize",
        "reduce",
        "set",
        "unique",
    },
    http = { "request", "status" },
    images = { "available", "clear_all", "place" },
    redraw = { "windows" },
    result = { "bind", "traverse" },
    task = { "all", "fail", "new", "of" },
}

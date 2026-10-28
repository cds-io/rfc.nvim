-- The cache as declared entries. Everything under the cache root is one of
-- three things: a fetched file, served from disk while young enough and
-- produced otherwise (an index, a document's text); a derived document,
-- rebuilt when its render is older than the current one or an input is
-- newer (a document, a source's subjects); and a memo, a parse of a file
-- redone when the file changes (what completion offers). An entry answers
-- Tasks, so a derived document composes over its inputs with bind, and a
-- new cached thing is declared, never reimplemented. The two rules, fresh
-- and current, are pure; the entries are a rim over the store's paths.
local rules = require("rfc.cache.rules")
return {
    fresh = rules.fresh,
    current = rules.current,
    fetched = require("rfc.cache.fetched").fetched,
    derived = require("rfc.cache.derived").derived,
}

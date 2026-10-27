-- The cache's entries over a temporary root. Runs inside Neovim (make test-nvim).
local cache = require("rfc.cache")
local store = require("rfc.store")
local help = require("rfc.help")
local Task = require("cds.task")

describe("cache", function()
    local cfg, notices, produced

    --- A fetched entry over a stub produce that counts its calls and
    --- answers `body` or fails with `err`.
    local function fetched(spec)
        return cache.fetched(
            cfg,
            vim.tbl_extend("force", {
                file = "thing.txt",
                label = "the thing",
                notify = function(msg, level)
                    table.insert(notices, { msg = msg, level = level })
                end,
                produce = function()
                    produced = produced + 1
                    return spec.err and Task.fail(spec.err) or Task.of(spec.body or "a\nb\n")
                end,
            }, spec)
        )
    end

    --- Runs a Task to completion on the loop; the value and the error.
    local function wait(task)
        local done, value, err = false, nil, nil
        task:run():on_complete(function(terr, v, e)
            value, err, done = v, terr and tostring(terr) or e, true
        end)
        vim.wait(2000, function()
            return done
        end)
        return value, err
    end

    local function touch(path, mtime)
        vim.uv.fs_utime(path, mtime, mtime)
    end

    before_each(function()
        cfg = { cache_dir = vim.fn.tempname() }
        notices, produced = {}, 0
        store.register(cfg)
    end)

    after_each(function()
        vim.fn.delete(cfg.cache_dir, "rf")
    end)

    describe("a fetched entry", function()
        it("produces, cleans, writes and answers when there is no copy", function()
            local e = fetched({ body = "a\r\nb\n" })
            assert.is_false(e:fresh())
            assert.are.same({ "a", "b" }, wait(e:lines()))
            assert.are.same({ "a", "b" }, vim.fn.readfile(e:path()))
            assert.are.equal(1, produced)
            assert.is_true(e:fresh())
        end)
        it("answers a fresh copy without producing", function()
            local e = fetched({ max_age = 60 })
            wait(e:lines())
            wait(e:lines())
            assert.are.equal(1, produced)
        end)
        it("produces again when the copy is older than max_age", function()
            local e = fetched({ max_age = 60 })
            wait(e:lines())
            touch(e:path(), os.time() - 61)
            wait(e:lines())
            assert.are.equal(2, produced)
        end)
        it("never ages without a max_age", function()
            local e = fetched({})
            wait(e:lines())
            touch(e:path(), os.time() - 10 * 24 * 3600)
            wait(e:lines())
            assert.are.equal(1, produced)
        end)
        it("produces again when the copy is a placeholder, and cached() hides it", function()
            local e = fetched({
                placeholder = function(lines)
                    return lines[1] == "stub"
                end,
            })
            vim.fn.writefile({ "stub" }, e:path())
            assert.is_nil(e:cached())
            assert.are.same({ "a", "b" }, wait(e:lines()))
            assert.are.equal(1, produced)
            assert.are.same({ "a", "b" }, e:cached())
        end)

        it("keeps the stale copy when atomic persistence refuses a refresh", function()
            local persist = require("cds.persist")
            local e = fetched({ max_age = 60, body = "replacement\n" })
            vim.fn.writefile({ "old" }, e:path())
            touch(e:path(), os.time() - 61)
            local real_write = persist.write_lines
            persist.write_lines = function()
                return nil, "disk full"
            end
            local called, lines, err = pcall(wait, e:lines())
            persist.write_lines = real_write
            assert.is_true(called)
            assert.is_nil(err)
            assert.are.same({ "old" }, lines)
            assert.are.same({ "old" }, vim.fn.readfile(e:path()))
            assert.are.equal(1, #notices)
            assert.is_truthy(notices[1].msg:find("disk full", 1, true))
        end)
        it("warns and answers the stale copy when producing fails", function()
            local e = fetched({ max_age = 60, err = "boom" })
            vim.fn.writefile({ "old" }, e:path())
            touch(e:path(), os.time() - 61)
            assert.are.same({ "old" }, wait(e:lines()))
            assert.are.same({
                { msg = "the thing could not be refreshed (boom); using the stale copy", level = vim.log.levels.WARN },
            }, notices)
        end)
        it("fails with the produce's error when there is no copy", function()
            local value, err = wait(fetched({ err = "boom" }):lines())
            assert.is_nil(value)
            assert.are.equal("boom", err)
            assert.are.same({}, notices)
        end)
        it("fails with a thrown error and writes nothing", function()
            local e = fetched({})
            e.produce = function()
                return Task.new(function()
                    error("thrown")
                end)
            end
            local value, err = wait(e:lines())
            assert.is_nil(value)
            assert.is_truthy(err:match("thrown"))
            assert.are.equal(0, vim.fn.filereadable(e:path()))
        end)
        it("memoises a parse per mtime, by name, across entries for one file", function()
            local e = fetched({})
            assert.is_nil(e:memo("n", function() end))
            wait(e:lines())
            local parses = 0
            local function count(lines)
                parses = parses + 1
                return #lines
            end
            assert.are.equal(2, e:memo("n", count))
            assert.are.equal(2, fetched({}):memo("n", count))
            assert.are.equal(1, parses)
            assert.are.equal(2, e:memo("other", count))
            assert.are.equal(2, parses)
            vim.fn.writefile({ "a", "b", "c" }, e:path())
            touch(e:path(), os.time() + 5)
            assert.are.equal(3, e:memo("n", count))
            assert.are.equal(3, parses)
        end)
        it("is not fresh when the index says the thing changed after the copy, and produces conditionally", function()
            local asked_since
            local e = fetched({ modified = os.time() + 100 })
            e.produce = function(since)
                asked_since = since
                produced = produced + 1
                return Task.of(false)
            end
            vim.fn.writefile({ "old" }, e:path())
            assert.is_false(e:fresh())
            assert.are.same({ "old" }, wait(e:lines()))
            assert.are.equal(1, produced)
            -- unchanged: the copy now carries the index's date, and is fresh
            assert.are.equal(e.modified, vim.uv.fs_stat(e:path()).mtime.sec)
            assert.is_true(e:fresh())
            assert.is_not_nil(asked_since)
        end)
        it("sets the file's mtime to the modification time a produce reports", function()
            local e = fetched({})
            e.produce = function()
                return Task.of({ body = "new\n", modified = 1700000000 })
            end
            assert.are.same({ "new" }, wait(e:lines()))
            assert.are.equal(1700000000, vim.uv.fs_stat(e:path()).mtime.sec)
        end)
        it("stamps a produced copy with the index's date when that is later than the server's time", function()
            local e = fetched({ modified = 1700100000 })
            e.produce = function()
                return Task.of({ body = "new\n", modified = 1700000000 })
            end
            assert.are.same({ "new" }, wait(e:lines()))
            assert.are.equal(1700100000, vim.uv.fs_stat(e:path()).mtime.sec)
            assert.is_true(e:fresh())
        end)
        it("passes no since when there is no copy", function()
            local asked = "unset"
            local e = fetched({})
            e.produce = function(since)
                asked = since
                return Task.of("a\n")
            end
            wait(e:lines())
            assert.is_nil(asked)
        end)
        it("produces into a cache directory deleted since", function()
            local e = fetched({ max_age = 60 })
            wait(e:lines())
            vim.fn.delete(cfg.cache_dir, "rf")
            assert.are.same({ "a", "b" }, wait(e:lines()))
            assert.are.equal(2, produced)
            assert.are.equal(1, vim.fn.filereadable(e:path()))
        end)
        it("answers the stale copy when producing throws after a fast-event resume", function()
            local e = fetched({ max_age = 60 })
            vim.fn.writefile({ "old" }, e:path())
            touch(e:path(), os.time() - 61)
            e.produce = function()
                return Task.new(function()
                    require("cds.async").await(1, function(cb)
                        local t = vim.uv.new_timer()
                        t:start(5, 0, function()
                            t:close()
                            cb()
                        end)
                    end)
                    error("thrown")
                end)
            end
            assert.are.same({ "old" }, wait(e:lines()))
            assert.are.equal(1, #notices)
            assert.is_truthy(
                notices[1].msg:match("^the thing could not be refreshed %(.*thrown%); using the stale copy$")
            )
        end)
    end)

    describe("a derived entry", function()
        local function derived(input, body)
            return cache.derived(cfg, {
                name = "rfc7",
                from = { input },
                version = help.RENDER,
                produce = function(lines)
                    return {
                        lines = { "*rfc7.txt*  D  *rfc7*", body or lines[1], "", help.MODELINE, help.FOOTER },
                        tags = { { name = "rfc7", line = 1 } },
                    }
                end,
            })
        end

        it("reuses one prepared model across help and Markdown and new entry descriptors", function()
            local input, parses, reads = fetched({}), 0, 0
            local cached = input.cached
            input.cached = function(self)
                reads = reads + 1
                return cached(self)
            end
            local function entry(version, context)
                return cache.derived(cfg, {
                    name = "rfc7",
                    from = { input },
                    version = version or help.RENDER,
                    context = context,
                    prepare = function(lines)
                        parses = parses + 1
                        return help.model("7", lines)
                    end,
                    render_model = help.render_model,
                })
            end
            local d = entry()
            assert.equals("rfc7", wait(d:ensure()))
            local before = reads
            local model = d:source_model()
            assert.is_true(model == entry():source_model())
            assert.equals(1, parses)
            assert.equals(before, reads)
            assert.same(help.render_model(model).lines, vim.fn.readfile(d:path()))
            assert.is_not_nil(require("rfc.document").from_model(model).anchors.rfc7)
            assert.is_not_nil(entry("next-version"):source_model())
            assert.equals(2, parses)
            assert.is_not_nil(entry("next-version", "another-url"):source_model())
            assert.equals(3, parses)
        end)

        it("prepares a warm disk export once and reevaluates dynamic source context", function()
            local input, parses = fetched({}), 0
            assert.equals("rfc7", wait(derived(input):ensure()))
            local url = "https://example.org/first/"
            local function entry()
                return cache.derived(cfg, {
                    name = "rfc7",
                    from = { input },
                    version = help.RENDER,
                    context = function()
                        return url
                    end,
                    prepare = function(lines)
                        parses = parses + 1
                        return help.model("7", lines)
                    end,
                    render_model = help.render_model,
                })
            end
            local d = entry()
            assert.equals("rfc7", wait(d:ensure()))
            assert.equals(0, parses)
            local first = d:source_model()
            assert.is_true(first == entry():source_model())
            assert.equals(1, parses)
            url = "https://example.org/second/"
            assert.is_false(d:current())
            assert.equals("rfc7", wait(d:ensure()))
            assert.equals(2, parses)
            assert.is_false(first == d:source_model())
            assert.is_true(d:current())
        end)

        it("invalidates a source plan when the ordered input set changes", function()
            local a = fetched({ file = "a.txt", body = "a" })
            local b = fetched({ file = "b.txt", body = "b" })
            assert.is_not_nil(wait(a:lines()))
            assert.is_not_nil(wait(b:lines()))
            local parses = 0
            local function entry(inputs)
                return cache.derived(cfg, {
                    name = "rfc7",
                    from = inputs,
                    version = help.RENDER,
                    prepare = function(first, second)
                        parses = parses + 1
                        return help.model("7", { first[1], second[1] })
                    end,
                    render_model = help.render_model,
                })
            end
            local first = entry({ a, b }):source_model()
            local reordered = entry({ b, a }):source_model()
            assert.is_false(first == reordered)
            assert.equals("a", first.blocks[1].text)
            assert.equals("b", reordered.blocks[1].text)
            assert.equals(2, parses)
        end)

        it("invalidates prepared models after same-second source replacement and removal", function()
            local input, parses = fetched({}), 0
            local d = cache.derived(cfg, {
                name = "rfc7",
                from = { input },
                version = help.RENDER,
                prepare = function(lines)
                    parses = parses + 1
                    return help.model("7", lines)
                end,
                render_model = help.render_model,
            })
            assert.equals("rfc7", wait(d:ensure()))
            local previous = d:source_model()
            local stamp = vim.uv.fs_stat(input:path()).mtime
            vim.wait(2)
            vim.fn.writefile({ "z", "b" }, input:path())
            vim.uv.fs_utime(input:path(), stamp.sec + stamp.nsec / 1e9, stamp.sec + stamp.nsec / 1e9)
            assert.is_false(previous == d:source_model())
            assert.is_false(d:current())
            assert.equals("rfc7", wait(d:ensure()))
            assert.is_false(previous == d:source_model())
            assert.equals(2, parses)
            assert.equals("z", vim.fn.readfile(d:path())[2])
            vim.fn.delete(input:path())
            local missing, err = d:source_model()
            assert.is_nil(missing)
            assert.matches("missing source input", err)
            assert.equals("rfc7", wait(d:ensure()))
            assert.equals(3, parses)
        end)

        it("does not retain failed preparations and isolates cache roots", function()
            local input, parses = fetched({}), 0
            assert.is_not_nil(wait(input:lines()))
            local function prepare(lines)
                parses = parses + 1
                if parses == 1 then
                    return nil, "try again"
                end
                return help.model("7", lines)
            end
            local d = cache.derived(cfg, {
                name = "rfc7",
                from = { input },
                version = help.RENDER,
                prepare = prepare,
                render_model = help.render_model,
            })
            local model, err = d:source_model()
            assert.is_nil(model)
            assert.equals("try again", err)
            assert.is_not_nil(d:source_model())
            assert.equals(2, parses)
            local other = cache.derived({ cache_dir = cfg.cache_dir .. "/other" }, {
                name = "rfc7",
                from = { input },
                version = help.RENDER,
                prepare = prepare,
                render_model = help.render_model,
            })
            assert.is_not_nil(other:source_model())
            assert.equals(3, parses)
        end)
        it("produces when the document is missing, then is current", function()
            local d = derived(fetched({}))
            assert.is_false(d:current())
            assert.are.equal("rfc7", wait(d:ensure()))
            assert.is_true(d:current())
            assert.are.equal("a", vim.fn.readfile(d:path())[2])
            local tags = vim.fn.readfile(store.doc_dir(cfg) .. "/tags")
            assert.is_truthy(vim.tbl_contains(tags, "rfc7\trfc7.txt\t/*rfc7*"))
        end)
        it("produces again when the document carries an older render", function()
            local d = derived(fetched({}))
            wait(d:ensure())
            local lines = vim.fn.readfile(d:path())
            lines[#lines] = " rfc.nvim render 1"
            vim.fn.writefile(lines, d:path())
            assert.is_false(d:current())
            wait(d:ensure())
            assert.are.equal(help.FOOTER, vim.fn.readfile(d:path())[5])
        end)
        it("produces again when an input is newer, and is current when they are of one second", function()
            local input = fetched({})
            local d = derived(input)
            wait(d:ensure())
            touch(input:path(), os.time() + 10)
            assert.is_false(d:current())
            touch(d:path(), os.time() + 10)
            assert.is_true(d:current())
        end)
        it("is not current when an input is missing, and produces it through the input", function()
            local input = fetched({})
            local d = derived(input)
            wait(d:ensure())
            vim.fn.delete(input:path())
            assert.is_false(d:current())
            wait(d:ensure())
            assert.are.equal(2, produced)
            assert.is_true(d:current())
        end)
        it("does not produce when current", function()
            local d = derived(fetched({}))
            wait(d:ensure())
            local before = vim.uv.fs_stat(d:path()).mtime.sec
            touch(d:path(), before - 100)
            touch(fetched({}):path(), before - 100)
            wait(d:ensure())
            assert.are.equal(before - 100, vim.uv.fs_stat(d:path()).mtime.sec)
        end)
        it("memoises a parse of the document per mtime, nil before it exists", function()
            local d = derived(fetched({}))
            local parses = 0
            local function count(lines)
                parses = parses + 1
                return #lines
            end
            assert.is_nil(d:memo("n", count))
            wait(d:ensure())
            assert.are.equal(5, d:memo("n", count))
            assert.are.equal(5, d:memo("n", count))
            assert.are.equal(1, parses)
        end)

        it("keeps a captured input revision separate from a concurrent replacement", function()
            local input = fetched({ file = "first.txt", body = "old" })
            assert.same({ "old" }, wait(input:lines()))
            local other = fetched({
                file = "second.txt",
                produce = function()
                    return Task.new(function()
                        vim.fn.writefile({ "new" }, input:path())
                        return "second"
                    end)
                end,
            })
            local d = cache.derived(cfg, {
                name = "rfc7",
                from = { input, other },
                version = help.RENDER,
                prepare = function(lines)
                    return help.model("7", lines)
                end,
                render_model = help.render_model,
            })
            assert.equals("rfc7", wait(d:ensure()))
            assert.is_false(d:current())
            assert.equals("new", d:source_model().blocks[1].text)
            assert.equals("rfc7", wait(d:ensure()))
            assert.is_true(d:current())
            assert.equals("new", vim.fn.readfile(d:path())[2])
        end)

        it("invalidates file and document memos on same-second rewrites", function()
            local input = fetched({})
            local d = derived(input)
            assert.equals("rfc7", wait(d:ensure()))
            local function first(lines)
                return lines[2] or lines[1]
            end
            assert.equals("b", input:memo("same-second", first))
            assert.equals("a", d:memo("same-second", first))
            local raw_stamp = vim.uv.fs_stat(input:path()).mtime.sec
            local doc_stamp = vim.uv.fs_stat(d:path()).mtime.sec
            vim.wait(2)
            vim.fn.writefile({ "z", "c" }, input:path())
            local lines = vim.fn.readfile(d:path())
            lines[2] = "z"
            vim.fn.writefile(lines, d:path())
            vim.uv.fs_utime(input:path(), raw_stamp, raw_stamp)
            vim.uv.fs_utime(d:path(), doc_stamp, doc_stamp)
            assert.equals("c", input:memo("same-second", first))
            assert.equals("z", d:memo("same-second", first))
        end)

        it("retries a source replaced during its read instead of mislabelling the snapshot", function()
            local input = fetched({ body = "old" })
            assert.same({ "old" }, wait(input:lines()))
            local read, changed = vim.fn.readfile, false
            vim.fn.readfile = function(path, ...)
                local lines = read(path, ...)
                if path == input:path() and not changed then
                    changed = true
                    vim.fn.writefile({ "new" }, path)
                end
                return lines
            end
            local ok, snapshot = pcall(function()
                return input:cached_snapshot()
            end)
            vim.fn.readfile = read
            assert.is_true(ok, tostring(snapshot))
            assert.same({ "new" }, snapshot.lines)
            assert.equals(require("rfc.revision").of(input:path()), snapshot.revision)
        end)
        it("passes a produce refusal through as the error", function()
            local d = cache.derived(cfg, {
                name = "rfc7",
                from = { fetched({}) },
                version = help.RENDER,
                produce = function()
                    return nil, "no good"
                end,
            })
            local value, err = wait(d:ensure())
            assert.is_nil(value)
            assert.are.equal("no good", err)
        end)
        it("produces again when an input is older than its max_age, with the document newer", function()
            local input = fetched({ max_age = 60 })
            local d = derived(input)
            wait(d:ensure())
            touch(input:path(), os.time() - 61)
            assert.is_false(d:current())
            wait(d:ensure())
            assert.are.equal(2, produced)
            assert.is_true(d:current())
        end)
    end)
end)

describe("derived source plans", function()
    it("prepares Markdown input without formatting help or modifying cached source", function()
        local lines = { "source" }
        local plan = { kind = "subjects", name = "test-subjects" }
        local derived = require("rfc.cache").derived({}, {
            name = "test",
            version = "test",
            from = {
                {
                    cached = function()
                        return lines
                    end,
                },
            },
            prepare = function(input)
                assert.is_true(input == lines)
                return plan
            end,
            produce = function()
                error("the help renderer is not needed")
            end,
        })
        assert.is_true(derived:source_model() == plan)
        assert.same({ "source" }, lines)
    end)
end)

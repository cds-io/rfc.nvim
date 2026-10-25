-- luacheck: no max line length (the cases hold HTML snippets as written)
local html = require("rfc.source.html")
local fp = require("cds.fp")
local fixtures = require("spec.fixtures")

local function kinds(blocks)
    return fp.map(blocks, function(b)
        return b.kind
    end)
end

--- Every block, the nested ones (a callout's, a quote's, a list item's, a
--- definition's) included, in order.
local function all_blocks(blocks)
    local out = {}
    local function walk(list)
        for _, b in ipairs(list) do
            table.insert(out, b)
            walk(b.blocks or {})
            for _, item in ipairs(b.items or {}) do
                walk(item)
            end
            for _, e in ipairs(b.entries or {}) do
                walk(e.blocks)
            end
        end
    end
    walk(blocks)
    return out
end

describe("blocks", function()
    it("reads a ReSpec heading: number from bdi.secno, id from the section", function()
        local b = html.blocks({ '<section id="sec-intro"><h2><bdi class="secno">1. </bdi>Introduction</h2></section>' })
        assert.are.same({
            kind = "heading",
            line = 1,
            level = 1,
            number = "1",
            id = "sec-intro",
            section = "sec-intro",
            text = { text = "Introduction", mentions = {} },
        }, b[1])
    end)
    it("reads a ReSpec heading with its own id, keeping the enclosing section's beside it", function()
        local b = html.blocks({
            '<section id="introduction"><h2 id="x1-introduction"><bdi class="secno">1. </bdi>Introduction</h2></section>',
        })
        assert.are.equal("x1-introduction", b[1].id)
        assert.are.equal("introduction", b[1].section)
    end)
    it("reads a Bikeshed heading: number from span.secno, text from span.content, id on the h", function()
        local b = html.blocks({
            '<h3 class="heading settled" id="grid-concepts"><span class="secno">1.1. </span><span class="content"> Background</span><a class="self-link" href="#grid-concepts"></a></h3>',
        })
        assert.are.same({
            kind = "heading",
            line = 1,
            level = 2,
            number = "1.1",
            id = "grid-concepts",
            text = { text = "Background", mentions = {} },
        }, b[1])
    end)
    it("reads an unnumbered heading and h6", function()
        assert.is_nil(html.blocks({ "<h2>Abstract</h2>" })[1].number)
        assert.are.equal(5, html.blocks({ "<h6>Deep</h6>" })[1].level)
    end)
    it("reads paragraphs with inline markup resolved and code in backticks", function()
        local b = html.blocks({ "<p>Use <code>id</code> and <em>care</em>,<br>twice.</p>" })
        assert.are.same({ "para" }, kinds(b))
        assert.are.equal("Use `id` and care,\ntwice.", b[1].text.text)
    end)
    it("keeps a pre as written, decoded, every inline tag stripped, with its language", function()
        local b = html.blocks({
            '<pre class="selected"><code class="hljs json">{ <span class="hljs-attr">"a"</span>: &lt;x&gt;',
            "  2 }</code></pre>",
        })
        assert.are.same({ kind = "code", line = 1, lang = "json", code = { '{ "a": <x>', "  2 }" } }, b[1])
        assert.are.equal("css", html.blocks({ '<pre class="lang-css"><c- c>x</c-></pre>' })[1].lang)
    end)
    it("flattens a hard break in a cell to a space, since a cell is one line", function()
        local b = html.blocks({ "<table><tr><td>a<br>b</td><td>c</td></tr></table>" })
        assert.are.equal("a b", b[1].rows[1][1].text)
    end)
    it("reads a table with its caption, header and cells, a cell's blocks joined", function()
        local b = html.blocks({
            '<table class="def"><caption><a class="self-link" href="#t1">Table <bdi>1</bdi></a><span class="table-title">Names</span></caption>',
            "<thead><tr><th>A</th><th>B</th></tr></thead><tbody><tr><td>1</td><td><p>x</p><p>y</p></td></tr></tbody></table>",
        })
        assert.are.equal("Table 1: Names", b[1].caption)
        assert.is_true(b[1].header)
        assert.are.same(
            { { "A", "B" }, { "1", "x y" } },
            fp.map(b[1].rows, function(r)
                return fp.map(r, function(c)
                    return c.text
                end)
            end)
        )
    end)
    it("reads lists, nested, ordered or not", function()
        local b = html.blocks({ "<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul><ol><li>d</li></ol>" })
        assert.are.same({ "list", "list" }, kinds(b))
        assert.is_false(b[1].ordered)
        assert.is_true(b[2].ordered)
        assert.are.equal("a", b[1].items[1][1].text.text)
        assert.are.equal("list", b[1].items[1][2].kind)
    end)
    it("reads a definition list", function()
        local b = html.blocks({ "<dl><dt>This version:</dt><dd><a href='https://x/'>https://x/</a></dd></dl>" })
        assert.are.equal("This version:", b[1].entries[1].term)
        assert.are.equal("https://x/", b[1].entries[1].blocks[1].text.text)
    end)
    it("reads a figure with its caption, alt and src as written; an object's fallback is the alt", function()
        local b = html.blocks({
            '<figure id="f"><img src="images/a.png" srcset="images/a.svg" alt="smart home"><figcaption><a class="self-link" href="#f">Figure <bdi class="figno">1</bdi></a> <span class="fig-title">Smart Home</span></figcaption></figure>',
            '<object data="images/b.png" type="image/png"><ol><li>one</li></ol></object>',
        })
        assert.are.same({
            kind = "figure",
            line = 1,
            id = "f",
            caption = "Figure 1: Smart Home",
            alt = "smart home",
            src = "images/a.png",
        }, b[1])
        assert.are.same({ kind = "figure", line = 2, alt = "1. one", src = "images/b.png" }, b[2])
    end)
    it("reads a bare image between paragraphs as a figure and drops decorative images", function()
        local b = html.blocks({
            '<p>Before</p><img src="a.png" alt="Diagram"><img src="decoration.png" alt=""><p>After</p>',
        })
        assert.are.same({ "para", "figure", "para" }, kinds(b))
        assert.are.same({ kind = "figure", line = 1, alt = "Diagram", src = "a.png" }, b[2])
        assert.are.equal("Before", b[1].text.text)
        assert.are.equal("After", b[3].text.text)
    end)
    it("reads the callouts of both generators with their labels", function()
        local b = html.blocks({
            '<aside class="example" id="e"><div class="marker"><a class="self-link" href="#e">Example <bdi>1</bdi></a><span class="example-title">: Sample</span></div><pre><code>{}</code></pre></aside>',
            '<div class="note"><div class="note-title"><span>Note</span></div><p>n</p></div>',
            '<p class="note" role="note"><span class="marker">Note:</span> bikeshed note</p>',
            '<div class="issue" id="i"><a class="self-link" href="#i"></a>problem</div>',
            "<details open><summary>More details about this document</summary><dl><dt>t</dt><dd>d</dd></dl></details>",
        })
        assert.are.same(
            { "Example 1: Sample", "Note", "Note", "Issue", "More details about this document" },
            fp.map(b, function(x)
                return x.label
            end)
        )
        assert.are.equal("code", b[1].blocks[1].kind)
        assert.are.equal("bikeshed note", b[3].blocks[1].text.text)
    end)
    it("renders a tabbed example as one callout per pane, labelled by its button, in button order", function()
        local b = html.blocks({
            '<button class="selected exampleTab1 A" onclick="x">Tab A</button><button class="exampleTab1 B">Tab B</button>',
            '<pre class="exampleTab1 A selected"><code>a</code></pre><pre class="exampleTab1 B"><code>b</code></pre>',
        })
        assert.are.same(
            { "Tab A", "Tab B" },
            fp.map(b, function(x)
                return x.label
            end)
        )
        assert.are.same({ "b" }, b[2].blocks[1].code)
    end)
    it(
        "drops the toc, the head logos, dialogs, dfn panels, screen-reader text and controls; a section is transparent",
        function()
            local b = html.blocks({
                '<nav id="toc"><ol class="toc"><li>x</li></ol></nav><div class="head"><img alt="W3C"></div><dialog>d</dialog><div class="dfn-panel">p</div>',
                '<span class="screenreader">|</span><input><button>b</button><section><p>kept</p></section>',
            })
            assert.are.same({ "para" }, kinds(b))
            assert.are.equal("kept", b[1].text.text)
        end
    )
    it("reads blockquote and hr", function()
        assert.are.same({ "quote", "rule" }, kinds(html.blocks({ "<blockquote><p>q</p></blockquote><hr>" })))
    end)
end)

describe("inline mentions", function()
    local function one(line)
        return html.blocks({ line })[1].text
    end
    it("makes a section mention of a link to a heading or section id", function()
        local t = html.blocks({ '<section id="s"><h2>S</h2><p>see <a href="#s">S</a></p></section>' })[2].text
        assert.are.same({ { kind = "section", section = "s", first = 5, last = 5 } }, t.mentions)
    end)
    it("makes a report mention of a fragment-free TR link, and text of one with a fragment", function()
        local t = one(
            '<p><a href="https://www.w3.org/TR/wot-architecture11/">Arch</a> and <a href="https://www.w3.org/TR/css-display-3/#box">box</a></p>'
        )
        assert.are.equal("Arch and box", t.text)
        assert.are.same({ { kind = "report", id = "wot-architecture11", first = 1, last = 4 } }, t.mentions)
    end)
    it("makes a reference mention of a bibref of either generator", function()
        local t = one(
            '<p><cite><a class="bibref" href="#bib-wot-architecture11">wot-architecture11</a></cite> <a data-link-type="biblio" href="#biblio-css-align-3">[CSS-ALIGN-3]</a></p>'
        )
        assert.are.same(
            { "wot-architecture11", "css-align-3" },
            fp.map(t.mentions, function(m)
                return m.id
            end)
        )
    end)
    it("keeps other links as text, with the URL once when the text is not the URL", function()
        assert.are.equal(
            "GitHub <https://github.com/x> and https://y/",
            one('<p><a href="https://github.com/x">GitHub</a> and <a href="https://y/">https://y/</a></p>').text
        )
        assert.are.equal("term", one('<p><a data-link-type="dfn" href="#dfn-term">term</a></p>').text)
    end)
    it("expands an abbr once, keeps ins and drops del, quotes q, keeps sup and var", function()
        assert.are.equal(
            "W3C (World Wide Web Consortium) and W3C",
            one(
                '<p><abbr title="World Wide Web Consortium">W3C</abbr> and <abbr title="World Wide Web Consortium">W3C</abbr></p>'
            ).text
        )
        assert.are.equal(
            "new “q” x® `v`",
            one("<p><ins>new</ins><del>old</del> <q>q</q> x<sup>®</sup> <var>v</var></p>").text
        )
    end)
end)

describe("head", function()
    it("reads the title, subtitle, metadata and abstract of a ReSpec report", function()
        local h = html.head(fixtures.read(fixtures.w3c_td))
        assert.are.equal("Web of Things (WoT) Thing Description 1.1", h.title)
        assert.is_truthy(h.subtitle:match("^W3C Recommendation"))
        assert.are.equal("This version:", h.meta[1].term)
        assert.is_truthy(h.abstract[1].text:match("^This document describes a formal information model"))
    end)
    it("reads a Bikeshed report's head the same way", function()
        local h = html.head(fixtures.read(fixtures.w3c_grid))
        assert.are.equal("CSS Grid Layout Module Level 2", h.title)
        assert.is_truthy(h.subtitle:match("Candidate Recommendation"))
    end)
end)

describe("over the excerpts", function()
    it("reads the Thing Description excerpt into the block kinds its sections hold", function()
        local b = all_blocks(html.blocks(fixtures.read(fixtures.w3c_td)))
        local k = fp.set(kinds(b))
        for _, want in ipairs({ "heading", "para", "code", "table", "list", "dl", "figure", "callout" }) do
            assert.is_true(k[want], want)
        end
    end)
    it("reads the Grid excerpt, custom elements inside pre and all", function()
        local b = all_blocks(html.blocks(fixtures.read(fixtures.w3c_grid)))
        local code = fp.find(b, function(x)
            return x.kind == "code"
        end)
        assert.is_truthy(code)
        assert.is_nil(fp.find(code.code, function(l)
            return l:find("<c-", 1, true)
        end))
    end)
end)

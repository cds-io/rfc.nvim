# rfc.nvim

RFCs, Ethereum's EIPs and ERCs, Bitcoin's BIPs, Solana's SIMDs and the
W3C's technical reports, as Neovim help. `:Rfc 9110` fetches the RFC's text from the RFC Editor;
`:Eip 1559`, `:Bip 32` and `:Simd 64` fetch a proposal's from its
repository; each is rendered as a help document and opened with `:help`,
so from then on the editor's own help navigation is the whole interface:

```
:help rfc9110            the RFC
:help rfc9110-3.1        a section, with completion over every cached document
:help eip1559-specification   a section of an EIP
CTRL-]                   follow a link: a section, a cited RFC or EIP, a reference entry
CTRL-T                   back through the tag stack, across documents
<CR>                     follow the first link on the line: Enter on a ToC row
]]  [[                   the next and the previous section, with a count
gO                       the contents beside the document; Enter opens a section, q closes
,tv                      the rich view on and off
:helpgrep MUST NOT       search every cached document into the quickfix list
```

A link to a document that is not cached yet (`|rfc2616|` in RFC 9110's
text, `|eip2718|` in EIP-1559's) fetches it on `CTRL-]` and then jumps.
The requirement keywords of RFC 2119 (MUST, SHOULD NOT, MAY) are
highlighted in bold.

A document opens in the rich view: a rule above every heading and the
heading highlighted, drawn over the text as extmarks, so `,tv` puts the
text back as written in place and the file on disk is the RFC plus its
tags and links either way. `gO` opens the contents beside the document,
one row per heading indented by level, its cursor on the section yours is
in; Enter there is `:help` on that section, so CTRL-T returns, and `q`
closes it.

A short explainer:

[![RFC viewer: rfc.nvim in use](https://img.youtube.com/vi/ivWq0YfZ8Dk/maxresdefault.jpg)](https://www.youtube.com/watch?v=ivWq0YfZ8Dk)

## Finding a document

One command per source, each with the same four forms, a fifth, `status`,
and a sixth, `subjects`, for a source that has them:

```
:Rfc                     the RFC index in vim.ui.select
:Rfc http semantics      the entries whose number or title match, fuzzily;
                         one match opens at once, several are offered
:Rfc 9110                an RFC by number
:Rfc rfc2616-14.4        a tag
:Rfc sem<Tab>            completion by number or title over the cached
                         index and the tags of cached RFCs
:Rfc status              the subjects on one status: the standards track
                         and the other categories, each with its count
:Rfc status internet standard   straight to the subjects filtered so
:Rfc subjects            the RFCs by subject, as one help document
:Rfc subjects dns        a subject by its slug or its name, else a search
                         over the subjects

:Eip                     EIPs and ERCs, one index
:Eip token standard      a search over it
:Eip 20                  ERC-20: the EIP and ERC numbers are one space
:Eip erc20               a tag, by either name
:Eip tok<Tab>            completion
:Eip status              Draft, Review, Last Call, Final, Living, Stagnant,
                         Withdrawn, each with its count; All first
:Eip status final        the subjects filtered to the Final proposals
:Eip subjects            the EIPs by category

:Bip                     the BIP index, the repository's README
:Bip taproot             a search over it
:Bip 32                  a BIP by number; `:Bip 0032` is the same one
:Bip 3<Tab>              completion
:Bip subjects            the BIPs by layer and by type

:Simd                    the SIMD index, the repository's proposals directory
:Simd receipt            a search over it
:Simd 64                 a SIMD by number
:Simd tr<Tab>            completion

:W3c                     the W3C technical reports index
:W3c web of things       a search over it
:W3c wot-thing-description11   a report by its shortname
:W3c w3c-css-grid-2#5.3  a tag: the shortname, then # and the section
:W3c wcag<Tab>           completion
:W3c subjects            the reports by maturity, tag and working group
```

A picked or completed item reads `eip20  Token Standard (Final)`: the tag
first, then the title, and the command takes the first word. The first
item a picker offers is the source's subjects, `eip-subjects  EIPs by
subject`, above the index and above a search's matches alike, so the
taxonomy is one Enter away (a picker's own typed filter may hide it once
the typed text stops matching). Completion cannot wait on the network, so
it offers what the last picker or search left in the cache; those fetch
an index that is missing or a day old.

## By status

Every source's documents move through a lifecycle, and its index says
where each stands: an RFC's category (PROPOSED STANDARD, INTERNET
STANDARD, INFORMATIONAL), an EIP's status (Draft, Review, Last Call,
Final, Living, Stagnant, Withdrawn), a BIP's (Draft, Complete, Deployed,
Closed), a W3C report's maturity (Draft Standard, Candidate Standard,
Standard, Note). The status cuts across the subjects: a Core EIP and an
ERC are each Draft or Final, so the filter is the subjects document's.

`:Eip status` offers the statuses in the lifecycle's order, each with its
count and `All` first. Choosing one renders `eip-subjects.txt` again with
only the proposals standing there: every category keeps its heading with
the count of what remains (`Core  (448)` reads `Core  (131)` under Final),
the `Status` root has that one child, and the title line reads
`*eip-subjects.txt*  EIPs by subject  [Status: Final]`. The document
opens at the section you were in, or at its top when that section has
nothing left. `:Eip status final` goes straight there, case aside,
`:Eip status all` puts everything back, and `:Eip status <Tab>` completes
the names. In the document, `gs` cycles the status: All, then each in
order, then All again; every window showing the document keeps its
section, and the contents sidebar follows.

The choice holds for the session and starts from `All`, or from the
status `setup()` names for the source:

```lua
require("rfc").setup({ sources = { eip = true }, status = { eip = "Final" } })
```

The SIMDs keep their status in each proposal's text, so theirs are known
once `:Simd subjects` has fetched the texts; `:Simd status` says so until
then.

## By subject

`:Rfc subjects` opens the RFCs by subject as one help document: a contents
block of every subject, indented by level, then one section per subject
listing the RFCs filed there as links. Everything a document has, this one
has too: `gO` is the tree as a sidebar, Enter or CTRL-] on a listed RFC
fetches and opens it, `]]` walks the subjects, `:helpgrep` searches them,
and `:help rfc-subjects-naming-dns` lands on a subject by its tag (the
path slugged, level by level). `:Rfc subjects dns` lands there too, and a
word that names no subject is a search over them.

The subjects come from the RFC Editor's subject tags
([rfc-editor/rfc-subject-tags](https://github.com/rfc-editor/rfc-subject-tags),
in beta): a curated tree of 19 roots, four levels at most, that their
pipeline assigns to every RFC and publishes daily as a CSV. The plugin
fetches that CSV as an index, kept a day like every index, and renders it;
an RFC sits under its deepest tags, and the count beside a subject is
every RFC under it, each counted once.

`:W3c subjects` has three roots, Maturity, Tags and Deliverers (the
working groups), so `:W3c subjects wot` lands on the Web of Things
reports and `:W3c subjects standard` on everything at Recommendation.
`:Eip subjects` has two roots: the site's six categories (Core,
Networking, Interface, ERC, Meta, Informational), with the hardfork meta
EIPs filed under `Meta / Hardforks` since their titles say so, and the
status, so `Status / Last Call` is the list of what is about to be final
across the categories (`:Eip subjects hardforks` and `:Eip subjects
last-call` land on those); `:Bip subjects` is the README's two columns,
Layer and Type, each a root. `:Simd subjects` is each proposal's
status, read from its frontmatter: the first open fetches every
proposal once (eight at a time) and keeps the texts, so a SIMD opened
afterwards is already in the store, and the document rebuilds only when
the directory gains one.

## Sources

Five sources, chosen in `setup`; only the RFC Editor is on by default.

| Source | Command | Tags | Text | Index | Subjects |
|---|---|---|---|---|---|
| `rfc` | `:Rfc` | `rfc9110`, `rfc9110-3.1` | rfc-editor.org | rfc-index.txt | the RFC Editor's subject tags, `rfc-tags.csv` |
| `eip` | `:Eip` | `eip1559`, `eip1559-specification`, `eip20` with `erc20` as its alias | github.com/ethereum/EIPs, then ethereum/ERCs | the six category pages of eips.ethereum.org, as one | the categories |
| `bip` | `:Bip` | `bip32`, `bip32-conventions`, `bip341-design` | github.com/bitcoin/bips | the repository's README | the README's Layer and Type |
| `simd` | `:Simd` | `simd64`, `simd64-summary` | github.com/solana-foundation/solana-improvement-documents | the proposals directory, through the GitHub API | each proposal's status, from its text |
| `w3c` | `:W3c` | `w3c-wcag22`, `w3c-css-grid-2#5.3` | www.w3.org/TR/<shortname>/ | www.w3.org/TR, the reports index | maturity, tags and working group, from the index |

EIPs and ERCs share one number space, so the `eip` source covers both
repositories: `:Eip 20` asks the EIPs repository, finds the stub that says
EIP-20 moved, and fetches ERC-20 from the ERCs repository instead. A
proposal in the ERC category is tagged by both names, so `|erc20|` in
another proposal's text and `:help erc20` land on it. The index is the
site's six category pages read as one, each number once, which is also
where a proposal's category comes from.

The BIPs are written in MediaWiki, a few of the newer ones in markdown, and
the `bip` source reads either: the preamble becomes the header, `==`
headings get tags, `<pre>` and `<source>` blocks become help code blocks,
wikitables become aligned columns, footnotes (`<ref>`) become numbered
notes where the references stand, and `[[bip-0340.mediawiki|BIP340]]`,
`[[bip-0341.mediawiki#design|...]]` and a bare `BIP 32` become links, to
the section when one is named.

A W3C report is HTML only, as ReSpec or Bikeshed writes it, and
`cds.html` reads either into the blocks the render folds: headings keep
their numbers and get tags (`w3c-css-grid-2#5.3`; the `#` splits the
shortname from the section, since shortnames carry dashes), prose wraps
at 78, code is fenced, tables are aligned under a caption line, lists and
definition lists indent, a figure is its caption, alt text and image URL
(`gx` opens it), and a note, example, issue, `details` or tabbed example
is a labelled block. Links to sections, to other reports and to the
references become `|tags|`; links to definitions stay text. A report is
fetched at the URL the index spells (`WCAG22`, not `wcag22`), and asked
for again with `If-Modified-Since` when the index dates it after the
copy, so a republished draft follows its publication.

The SIMDs are markdown with a frontmatter, read as the EIPs are. The
repository has no listing page, so the index is the `proposals` directory
as the GitHub API lists it: the picker's titles come from the file names
(`0064-transaction-receipt.md` reads "Transaction Receipt"), and a
number finds its file there before the text is fetched; the directory is
kept a day, as every index is.

This is a personal plugin on the functional-core-with-editor-rims pattern
the plugins in this directory share, developed with help from a coding
agent. The idea of reading RFCs inside Neovim, and the ToC and reference
following that make it worthwhile, come from must.nvim; the code here is
written fresh around Neovim's help system. It requires Neovim 0.13
(`vim.async`) and `curl`.

Thanks to [@gnidan](https://github.com/gnidan) for the feedback that
shaped the commands: `:Rfc` for the IETF alone, `:Eip` for the proposals,
and no ERC to tell apart from an EIP.

## How it works

A source is one record (`lua/rfc/sources.lua`): where its text and its
index come from, how the index reads, and how the text renders. The
pipeline is the same for both: fetch, clean, render, write, then `:help`.

An RFC's text is parsed by `cds.rfc` and rendered by a pure, total function
(`lua/rfc/help.lua`) into a help document: a tag on every heading and reference
entry, the table of contents' numbers turned into links, and every "Section
3.1", "RFC 2616" and "[CACHING]" in the body turned into a link to its target.
Nothing in the text is changed otherwise.

A proposal's markdown is parsed by `cds.eip` (frontmatter, headings,
fenced code, the EIPs and ERCs a line names, the listing page) and rendered
by `lua/rfc/help_eip.lua`: the frontmatter becomes a header block, the
headings get tags and a table of contents of links, fenced code becomes
help code blocks, an ordered list written `1. 1. 1.` is numbered as
markdown means it, and every `[EIP-2718](./eip-2718.md)` or bare `EIP-155`
becomes a link.

The rendered document is written under the cache directory's `doc/`, and
that directory is appended to the runtimepath, so `:help` reads it as it
reads any plugin's documentation. The tags file is written by the plugin
from the tags the render declared, since `:helptags` would read the `*/*`
media ranges in an RFC's text as tags too.

The cache is `stdpath("cache")/rfc/`: each text as fetched (`rfc9110.txt`,
`eip1559.md`, `bip32.txt`, `simd64.md`), its document (`doc/rfc9110.txt`),
the tags file, each source's index and the RFC subject tags
(`rfc-subjects.csv`), fetched again when more than a day old, and each
source's subjects document (`doc/rfc-subjects.txt`), rendered again when
its index is newer. Delete the directory to start over.

A report's figures and wide tables get more in the rich view. Where an
image plugin is loaded and the terminal can draw (image.nvim under kitty
or ghostty, through `cds.images`, the one module that names the plugin),
each figure's image is drawn below its URL line; without one the caption,
alt and URL read as text. A table wider than the page is folded under its
caption, with each row laid out as its first cell over `Label: text`
lines in virtual text; `zo` shows the aligned rows, and `,tv` puts both
back as written.

Everything in it is one of three cache entries (`lua/rfc/cache.lua`): a
fetched file, served from disk while young enough and fetched otherwise
(the stale copy stands in, with a warning, when the fetch fails); a
derived document, rebuilt when the render that wrote it is older than
the current one or an input is newer, missing or no longer fresh; and a
memo, a parse of a file that
completion redoes only when the file changes. A new source or a new
derived document declares its entry in a few lines and reimplements none
of this.

## Installation

With lazy.nvim:

```lua
{ "cds-io/rfc.nvim" }
```

The plugin's `lazy.lua` declares its one dependency,
[cds-lua](https://github.com/cds-io/cds-lua), the family's house library,
tracking its main; lazy.nvim 11 and later installs it with the plugin. With
another plugin manager, install `cds-io/cds-lua` alongside. At startup the
plugin checks that the cds-lua present provides what it uses (`rfc.needs`)
and, when something is missing, says so and what to install instead of
failing later.

`setup` is optional:

```lua
require("rfc").setup({
    sources = { rfc = true, eip = false, bip = false, simd = false, w3c = false },
    cache_dir = nil, -- stdpath("cache") .. "/rfc"
    view = "rich", -- or "plain": a document as written
    toc = { width = 44 }, -- the contents sidebar
    -- where messages go; vim.notify with an "rfc: " prefix by default
    notify = function(msg, level, opts) end,
})
```

`require("rfc").activity()` is a statusline segment naming the fetches
out, with their seconds; `User RfcActivity` fires when one starts or ends.

`:help rfc.nvim` is the manual: the commands, the keys, the status and
subject filters, each source, the cache and `setup`'s settings. It is
generated from the annotation blocks in `lua/rfc/init.lua` and
`lua/rfc/config.lua` by [mini.doc](https://github.com/nvim-mini/mini.doc)
(`make doc`), and `make check` refuses a stale copy.


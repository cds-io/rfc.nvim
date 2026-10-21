# rfc.nvim

RFCs, Ethereum's EIPs and ERCs, Bitcoin's BIPs and Solana's SIMDs, as
Neovim help. `:Rfc 9110` fetches the RFC's text from the RFC Editor;
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

Two commands, one per source, each with the same four forms:

```
:Rfc                     the RFC index in vim.ui.select
:Rfc http semantics      the entries whose number or title match, fuzzily;
                         one match opens at once, several are offered
:Rfc 9110                an RFC by number
:Rfc rfc2616-14.4        a tag
:Rfc sem<Tab>            completion by number or title over the cached
                         index and the tags of cached RFCs

:Eip                     EIPs and ERCs, one index
:Eip token standard      a search over it
:Eip 20                  ERC-20: the EIP and ERC numbers are one space
:Eip erc20               a tag, by either name
:Eip tok<Tab>            completion

:Bip                     the BIP index, the repository's README
:Bip taproot             a search over it
:Bip 32                  a BIP by number; `:Bip 0032` is the same one
:Bip 3<Tab>              completion

:Simd                    the SIMD index, the repository's proposals directory
:Simd receipt            a search over it
:Simd 64                 a SIMD by number
:Simd tr<Tab>            completion
```

A picked or completed item reads `eip20  Token Standard (Final)`: the tag
first, then the title, and the command takes the first word. Completion
cannot wait on the network, so it offers what the last picker or search
left in the cache; those fetch an index that is missing or a day old.

## Sources

Four sources, chosen in `setup`; only the RFC Editor is on by default.

| Source | Command | Tags | Text | Index |
|---|---|---|---|---|
| `rfc` | `:Rfc` | `rfc9110`, `rfc9110-3.1` | rfc-editor.org | rfc-index.txt |
| `eip` | `:Eip` | `eip1559`, `eip1559-specification`, `eip20` with `erc20` as its alias | github.com/ethereum/EIPs, then ethereum/ERCs | eips.ethereum.org/all and ercs.ethereum.org/all, as one |
| `bip` | `:Bip` | `bip32`, `bip32-conventions`, `bip341-design` | github.com/bitcoin/bips | the repository's README |
| `simd` | `:Simd` | `simd64`, `simd64-summary` | github.com/solana-foundation/solana-improvement-documents | the proposals directory, through the GitHub API |

EIPs and ERCs share one number space, so the `eip` source covers both
repositories: `:Eip 20` asks the EIPs repository, finds the stub that says
EIP-20 moved, and fetches ERC-20 from the ERCs repository instead. A
proposal in the ERC category is tagged by both names, so `|erc20|` in
another proposal's text and `:help erc20` land on it, and the index is both
listing pages with each number once.

The BIPs are written in MediaWiki, a few of the newer ones in markdown, and
the `bip` source reads either: the preamble becomes the header, `==`
headings get tags, `<pre>` and `<source>` blocks become help code blocks,
wikitables become aligned columns, footnotes (`<ref>`) become numbered
notes where the references stand, and `[[bip-0340.mediawiki|BIP340]]`,
`[[bip-0341.mediawiki#design|...]]` and a bare `BIP 32` become links, to
the section when one is named.

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
help code blocks, and every `[EIP-2718](./eip-2718.md)` or bare `EIP-155`
becomes a link.

The rendered document is written under the cache directory's `doc/`, and
that directory is appended to the runtimepath, so `:help` reads it as it
reads any plugin's documentation. The tags file is written by the plugin
from the tags the render declared, since `:helptags` would read the `*/*`
media ranges in an RFC's text as tags too.

The cache is `stdpath("cache")/rfc/`: each text as fetched (`rfc9110.txt`,
`eip1559.md`, `bip32.txt`, `simd64.md`), its document (`doc/rfc9110.txt`), the tags file and each
source's index, fetched again when it is more than a day old. Delete the
directory to start over.

## Installation

With lazy.nvim:

```lua
{ dir = "~/dev/nvim-plugins/rfc.nvim" }
```

`setup` is optional:

```lua
require("rfc").setup({
    sources = { rfc = true, eip = false, bip = false, simd = false },
    cache_dir = nil, -- stdpath("cache") .. "/rfc"
    view = "rich", -- or "plain": a document as written
    toc = { width = 44 }, -- the contents sidebar
    -- where messages go; vim.notify with an "rfc: " prefix by default
    notify = function(msg, level, opts) end,
})
```

`require("rfc").activity()` is a statusline segment naming the fetches
out, with their seconds; `User RfcActivity` fires when one starts or ends.


# rfc.nvim

RFCs, and Ethereum's EIPs and ERCs, as Neovim help. `:Rfc 9110` fetches
the RFC's text from the RFC Editor, renders it as a help document and
opens it with `:help`, so from then on the editor's own help navigation is
the whole interface:

```
:help rfc9110            the RFC
:help rfc9110-3.1        a section, with completion over every cached document
:help eip1559-specification   a section of an EIP
CTRL-]                   follow a link: a section, a cited RFC or EIP, a reference entry
CTRL-T                   back through the tag stack, across documents
<CR>                     follow the first link on the line: Enter on a ToC row
:helpgrep MUST NOT       search every cached document into the quickfix list
```

A link to a document that is not cached yet (`|rfc2616|` in RFC 9110's
text, `|eip2718|` in EIP-1559's) fetches it on `CTRL-]` and then jumps.
`:Rfc` with no argument offers the indices of the enabled sources through
`vim.ui.select`; `:Rfc rfc2616-14.4`, `:Rfc eip1559` and `:Rfc erc20` open
a tag directly. The requirement keywords of RFC 2119 (MUST, SHOULD NOT,
MAY) are highlighted in bold.

## Sources

Three sources, chosen in `setup`; only the RFC Editor is on by default.

| Source | Tags | Text | Index |
|---|---|---|---|
| `rfc` | `rfc9110`, `rfc9110-3.1` | rfc-editor.org | rfc-index.txt |
| `eip` | `eip1559`, `eip1559-specification` | github.com/ethereum/EIPs | eips.ethereum.org/all |
| `erc` | `erc20` (and `eip20`), `erc20-methods` | github.com/ethereum/ERCs | ercs.ethereum.org/all |

An ERC carries its EIP number as a second tag, so `|eip20|` in another
proposal's text lands on ERC-20. EIP-20 in the EIPs repository is a stub
that says it moved; its document links to `|erc20|`.

This is a personal plugin on the functional-core-with-editor-rims pattern
the plugins in this directory share, developed with help from a coding
agent. The idea of reading RFCs inside Neovim, and the ToC and reference
following that make it worthwhile, come from must.nvim; the code here is
written fresh around Neovim's help system. It requires Neovim 0.13
(`vim.async`) and `curl`.

## How it works

A source is one record (`lua/rfc/sources.lua`): where its text and its
index come from, how the index reads, and how the text renders. The two
Ethereum sources come from one constructor, since both are a markdown file
in a repository plus a listing page. The pipeline is the same for all:
fetch, clean, render, write, then `:help`.

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
`eip1559.md`), its document (`doc/rfc9110.txt`), the tags file and each
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
    sources = { rfc = true, eip = false, erc = false },
    cache_dir = nil, -- stdpath("cache") .. "/rfc"
    -- where messages go; vim.notify with an "rfc: " prefix by default
    notify = function(msg, level, opts) end,
})
```

`require("rfc").activity()` is a statusline segment naming the fetches
out, with their seconds; `User RfcActivity` fires when one starts or ends.


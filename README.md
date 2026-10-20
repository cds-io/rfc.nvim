# rfc.nvim

RFCs as Neovim help. `:Rfc 9110` fetches the RFC's text from the RFC
Editor, renders it as a help document and opens it with `:help`, so from
then on the editor's own help navigation is the whole interface:

```
:help rfc9110            the RFC
:help rfc9110-3.1        a section, with completion over every cached RFC
CTRL-]                   follow a link: a section, a cited RFC, a reference entry
CTRL-T                   back through the tag stack, across RFCs
<CR>                     follow the first link on the line: Enter on a ToC row
:helpgrep MUST NOT       search every cached RFC into the quickfix list
```

A link to an RFC that is not cached yet (`|rfc2616|` in RFC 9110's text)
fetches it on `CTRL-]` and then jumps. `:Rfc` with no argument offers the
RFC index through `vim.ui.select`; `:Rfc rfc2616-14.4` opens a tag
directly. The requirement keywords of RFC 2119 (MUST, SHOULD NOT, MAY) are
highlighted in bold.

This is a personal plugin on the functional-core-with-editor-rims pattern
the plugins in this directory share, developed with help from a coding
agent. The idea of reading RFCs inside Neovim, and the ToC and reference
following that make it worthwhile, come from must.nvim; the code here is
written fresh around Neovim's help system. It requires Neovim 0.13
(`vim.async`) and `curl`.

## How it works

The RFC's text is parsed by `cds.rfc` (`lua/cds/rfc.lua`, a module of the
house library: the table of contents with each heading's line, the
references and what an entry cites, the mentions a line makes, the RFC
index) and rendered by a pure, total function (`lua/rfc/help.lua`)
into a help document: a tag on every heading and reference entry, the table
of contents' numbers turned into links, and every "Section 3.1", "RFC 2616"
and "[CACHING]" in the body turned into a link to its target. Nothing in
the text is changed otherwise.

The rendered document is written under the cache directory's `doc/`, and
that directory is appended to the runtimepath, so `:help` reads it as it
reads any plugin's documentation. The tags file is written by the plugin
from the tags the render declared, since `:helptags` would read the `*/*`
media ranges in an RFC's text as tags too.

The cache is `stdpath("cache")/rfc/`: the text as fetched (`rfc9110.txt`),
the document (`doc/rfc9110.txt`), the tags file and the RFC index, which is
fetched again when it is more than a day old. Delete the directory to start
over.

## Installation

With lazy.nvim:

```lua
{ dir = "~/dev/nvim-plugins/rfc.nvim" }
```

`setup` is optional:

```lua
require("rfc").setup({
    cache_dir = nil, -- stdpath("cache") .. "/rfc"
    -- where messages go; vim.notify with an "rfc: " prefix by default
    notify = function(msg, level, opts) end,
})
```

`require("rfc").activity()` is a statusline segment naming the fetches
out, with their seconds; `User RfcActivity` fires when one starts or ends.

## Development

`make check` runs the pure specs under busted, the editor specs under
busted inside Neovim (nlua), selene and stylua. The editor specs point the
store at a temporary directory and replace the network with fixture text;
`lua/cds/` is the house library in calplus's style: `rfc.lua` has its home
here, and the rest is copied from calplus unchanged.

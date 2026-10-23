-- A W3C technical report, read: the HTML the two generators the W3C uses
-- (ReSpec and Bikeshed) emit, as tokens (`cds.html.tokens`), as a tree
-- (`cds.html.tree`), as inline text with mentions (`cds.html.inline`) and
-- as the blocks a renderer folds over (`cds.html.blocks`). This is the
-- surface: the tokenizer's three functions and the reader's two. Plain
-- lines in, plain tables out; nothing here names the editor.
local tokens = require("cds.html.tokens")
local blocks = require("cds.html.blocks")

return {
  tokens = tokens.tokens,
  decode = tokens.decode,
  squash = tokens.squash,
  blocks = blocks.blocks,
  head = blocks.head,
}

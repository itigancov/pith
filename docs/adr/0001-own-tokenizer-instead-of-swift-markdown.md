# Own tokenizer instead of swift-markdown

We write the Markdown parser ourselves: a line-by-line block scanner plus an inline parser following simplified CommonMark (flanking rules, code spans are opaque). We do not use `swift-markdown`. It produces a full AST, while we need Spans with exact ranges, Markers that stay visible, and per-edit reparsing of only the changed Blocks. A custom parser is easier to make incremental, has no external dependencies, and ports easily into the future product.

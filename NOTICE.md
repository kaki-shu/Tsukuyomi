# Open Source / Reference Notes

Tsukuyomi itself is published under the MIT License. See `LICENSE`.

This public version of Tsukuyomi includes or references the following open-source work where it directly informed the implementation.

## Included dependency

### SwiftSoup

- Repository: https://github.com/scinfu/SwiftSoup
- License: MIT
- Usage in this project: HTML parsing and article content extraction support

## Referenced implementation patterns

### SakuraRSS

- Repository: https://github.com/katagaki/SakuraRSS
- License status at review time: no GitHub-recognized license metadata detected on 2026-06-15
- Usage in this project: article extraction cleanup ideas, YouTube feed discovery patterns, and reader-flow refinements that were adapted into Tsukuyomi
- Public-repo handling: this repository treats SakuraRSS as a reference source for implementation ideas and does not intentionally vendor its code or bundled media in the tracked public tree

No third-party images, fonts, or bundled media are intentionally redistributed in the tracked application source tree as part of this public cleanup pass.

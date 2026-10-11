# Extras

Optional mascot packs that are **not** part of Clamshell's MIT-licensed code. Each pack has its own folder and its own
`NOTICE.md` saying who owns it and under what terms it may be used.

| Pack | What it is |
| --- | --- |
| [`claude-crab/`](claude-crab/) | The pixel crab used by Claude Code. Not original to this project — read its NOTICE |

**Use one:** double-click its `.clamshellmascot` folder (Clamshell must be installed), or open Clamshell's menu →
*Mascot* → *Import GIF…* with your own animation.

**Bundle them into a build:**

```bash
./scripts/build-app.sh --with-extras
```

A normal build (`./scripts/build-app.sh`) does not include anything from this folder.

**Add your own pack:** make a folder `extras/<name>/` containing a `<Name>.clamshellmascot` pack (see the main README for the
format) and a `NOTICE.md` describing its licence.

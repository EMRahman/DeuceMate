# AGENTS.md

This repository is developed entirely via AI coding agents. The full agent
operating guide — architecture, build/test commands, the "no toolchain in
this container" reality, multi-site change recipes, and known AI traps — lives
in **[`CLAUDE.md`](./CLAUDE.md)**.

**Read `CLAUDE.md` at the start of every session, before writing any code.**
It is the single source of truth so guidance never drifts between files.
Skipping it means missing the multi-site change recipes and known traps that
produce silent bugs with no compiler errors — the cost of reading it is low;
the cost of missing it is not.

**Keep these files current.** If you notice that `CLAUDE.md` or `AGENTS.md`
contains a stale recipe, an outdated file size, or a resolved trap, fix it in
the same PR as your code change. Stale entries are actively harmful. The same
obligation applies to the `docs/architecture/` documents (see `CLAUDE.md` §6).

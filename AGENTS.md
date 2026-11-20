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

## After opening a pull request

- Stay with the PR and check it every minute for up to 10 minutes from when
  you opened it. Check the conversation, reviews, inline comments, and reactions.
- Review and address any feedback you find. Push fixes as needed and continue
  checking within the original 10-minute window.
- Treat a 👍 reply or reaction as approval to merge only if it comes from a
  coding agent that reviewed the PR. Attempt the merge once you have addressed
  outstanding feedback and confirmed that your GitHub credentials have write
  access to the target repository. Stop checking when the PR merges or the
  original 10-minute window ends.
- If the PR is still open when the window ends, report its status and any
  remaining feedback or merge blockers.

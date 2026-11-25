# Lessons on the way of working

This file holds the lessons learnt on the way of working. Each has its date, its source and what
to do. Read them at the start of a session, with `CLAUDE.md`. A lesson that becomes a rule moves
into `CLAUDE.md`, and this file says so.

## When is a review verdict posted?

As soon as its round ends, one comment per round. When no pull request exists yet, the verdicts
are posted one by one when it opens.

- Date: 2026-11-25. Source: audit 0011, F4.
- What went wrong: on PR #4 we posted the rounds of each of two commits, 39635f6 and 74cb34c, in
  one comment, with the commit. An audit could then check only a summary, not each finding.

## In which language are the owner's words quoted on GitHub?

In English, like everything else in the repository and on GitHub. The owner's words are
translated, and the comment says that they are.

- Date: 2026-11-25. Source: audit 0011, F5.
- What went wrong: two comments of PR #4 quoted the owner in Italian. We edited them and added a
  note to each.

## Who watches CI?

Only the main session. Agents never watch CI or poll its status. An agent that pushes reports
and stops: it does not wait for the run. Reading the result of a finished run once, as the
auditor does, is not watching.

- Date: 2026-11-25. Source: the owner's decision of that day, adopted for roadmap 0.6.
- Why: agents that poll CI use up GitHub's API limit, which the whole session shares.

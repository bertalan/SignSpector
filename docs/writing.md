# How we write

Rules for every text in this repository: README, design, roadmap, CLAUDE.md, agent prompts,
comments, commit messages, PR texts, the user guide and the strings the tool shows.

## Who reads our texts?

A person looking for one answer. They arrive with a question ("does it work offline?",
"what happens if the file already exists?") and leave when they have the answer. We write so
that they find it fast and can trust it.

## How is a document organised?

As questions and answers. Each section heading is a question the reader would ask, in their
words: "Which files does SignSpector open?", not "File discovery". The first sentence under
the heading answers it. Reasons, details and exceptions come after.

Requirement and step numbers stay (R16, 3.4): code and tests refer to them. They go at the
end of the answer, not in the heading.

## How long is a sentence?

At most about 20 words, one idea per sentence, active voice. Instructions use the imperative:
"Run `cargo nextest run`", not "The tests can be run with...". One term per thing: if it is
an "envelope" in one place, it is not a "container" two lines later.

## What is never shortened or reworded?

Code, commands, paths, file names, option names, error messages, numbers, versions and
dates. They are copied exactly, in backticks. Negations (not, never, only, except) are never
dropped to save words.

## What do we cut?

Anything that does not answer the question:

- greetings, recaps, "in summary", "let me know", "I hope this helps";
- hedging piled on hedging ("could potentially perhaps"): say what is known and what is not;
- filler: "in order to", "it is important to note that", "at its core";
- generic endings ("the future looks bright").

## Which patterns make a text sound machine-made?

We avoid them. The list comes from Wikipedia's "Signs of AI writing" (via the humanizer
guide):

- inflated significance: "plays a pivotal role", "is a testament to", "marks a shift";
- the usual vocabulary: crucial, delve, enhance, foster, intricate, landscape, leverage,
  seamless, showcase, tapestry, underscore, vibrant;
- "serves as", "stands as", "boasts" instead of "is" or "has";
- "not just X, but Y" and "it's not about X, it's about Y";
- lists of three by reflex, and synonyms rotated to avoid repeating a word;
- false ranges: "from small offices to large institutions";
- em dashes as decoration, emojis, curly quotes;
- bold words scattered in running text, and lists where every item starts with a bold
  label and a colon;
- Title Case In Headings (we write headings in sentence case);
- vague sources: "experts say", "it is widely recognised".

## Do our texts have a voice?

Yes, a plain one. We state decisions and say why: "The release embeds the EU list of lists
and the Italian list only: embedding all of them would add megabytes, and the first run with
a network refreshes them." We say what we do not know: "Not tested on Windows on ARM." We use "we" for the project. A text with no opinion and no reason is
not neutral, it is useless.

## Are there exceptions?

- Safety warnings and irreversible actions: full sentences, even if longer. Clarity beats
  brevity.
- Steps that must happen in order: a numbered list, one action per step.
- Tables: only when the reader compares values across rows.
- Strings shown by the tool follow the same rules in every language (R27), and must work
  with screen readers (R35): words, not symbols.

## Who checks?

The author, before committing: read the text once as the reader with the question. The
`fable-reviewer` and `coherence-auditor` agents check the patterns above in every review.
No text is sent to tools or models outside this subscription to be rewritten.

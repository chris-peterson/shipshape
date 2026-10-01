#!/usr/bin/env bash
# Print a guide's content: its lines with HTML comment spans and leading blanks
# removed. One test of content decides both whether a guide is filled in and
# what gets carried out, so a seeded template explains itself without becoming
# an instruction. Spans are matched across the line rather than at its start, so
# an inline `<!-- note -->` neither leaks nor takes the instruction beside it
# with it.
#
# Usage:  guide-content.sh <file>
#
# Exit:   0 = content printed (nothing, for an unfilled guide)
#         1 = the file can't be read

# covers: GUIDE-04
set -euo pipefail

if [ ! -r "${1:-}" ]; then
  printf 'guide-content: cannot read "%s"\n' "${1:-}" >&2
  exit 1
fi

awk '
  {
    rest = $0; out = ""; touched = inc
    while (length(rest) > 0) {
      if (inc) {
        p = index(rest, "-->")
        if (p == 0) { rest = ""; break }
        inc = 0; touched = 1; rest = substr(rest, p + 3)
      } else {
        p = index(rest, "<!--")
        if (p == 0) { out = out rest; rest = ""; break }
        out = out substr(rest, 1, p - 1)
        inc = 1; touched = 1; rest = substr(rest, p + 4)
      }
    }
    sub(/[[:space:]]+$/, "", out)
    if (out == "" && touched) next        # the line was comment through and through
    if (!started && out == "") next       # leading blanks
    started = 1
    print out
  }
  END {
    # Silence with no signal is the failure mode here: an unclosed comment
    # swallows the rest of the document, and the reader would just go quiet.
    if (inc) print "shipshape: unclosed <!-- in " FILENAME "; the rest of the document was read as a comment." > "/dev/stderr"
  }
' "$1"

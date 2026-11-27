#!/usr/bin/env python3
"""Heuristic ASD-STE100 linter. Scores violations per 100 words.

Not a certified STE checker. It covers the mechanical, deterministic subset of
the rules, which is where most machine-written slop concentrates.

Usage:
    python3 linter.py draft.md [more.md ...] [--strict] [--quiet]

--strict  enforce the 20-word instruction cap on every sentence and turn on the
          dictionary-substitution checks in full.
--quiet   print the score only.
"""

import argparse
import re
import sys
from pathlib import Path

# --- rule tables -------------------------------------------------------------

SUBSTITUTIONS = {
    "utilize": "use", "utilizes": "uses", "utilizing": "using", "leverage": "use",
    "initiate": "start", "commence": "start", "terminate": "stop", "cease": "stop",
    "facilitate": "help", "ensure": "make sure", "obtain": "get", "acquire": "get",
    "demonstrate": "show", "additionally": "also", "furthermore": "also",
    "moreover": "also", "therefore": "so", "thus": "so", "hence": "so",
    "consequently": "so", "however": "but", "nevertheless": "but",
    "approximately": "about", "sufficient": "enough", "numerous": "many",
    "regarding": "about", "concerning": "about", "attempt": "try",
    "assist": "help", "require": "need", "requires": "needs", "modify": "change",
    "indicate": "show", "indicates": "shows", "permit": "let", "retain": "keep",
    "transmit": "send", "verify": "check", "identify": "find", "subsequent": "after",
}

PHRASES = {
    r"\bprior to\b": "before",
    r"\bsubsequent to\b": "after",
    r"\bin order to\b": "to",
    r"\bin the event that\b": "if",
    r"\bdue to the fact that\b": "because",
    r"\bat this point in time\b": "now",
    r"\bthe majority of\b": "most",
    r"\bis capable of\b": "can",
    r"\bhas the ability to\b": "can",
    r"\bit is necessary (that|to)\b": "must",
    r"\bwith respect to\b": "about",
    r"\bin the vicinity of\b": "near",
    r"\bit is important to note that\b": "(delete)",
    r"\bit is worth (noting|mentioning) that\b": "(delete)",
    r"\bit should be noted that\b": "(delete)",
    r"\bin conclusion\b": "(delete)",
    r"\blet's dive in\b": "(delete)",
    r"\bperform (a|an) \w+ (of|on)\b": "use a verb",
    r"\bmake a decision\b": "decide",
    r"\bprovide a description\b": "describe",
    r"\bspin up\b": "start",
    r"\bstand up\b": "create",
    r"\btear down\b": "remove",
    r"\bblow away\b": "delete",
    r"\btrack down\b": "find",
    r"\bcarry out\b": "do",
    r"\bcome up with\b": "design",
    r"\bfigure out\b": "solve",
    r"\btake care of\b": "handle",
    r"\bput in place\b": "install",
}

MARKETING = {
    "seamless", "seamlessly", "robust", "powerful", "cutting-edge", "world-class",
    "next-generation", "revolutionary", "game-changing", "effortless", "effortlessly",
    "blazing", "lightning-fast", "delightful", "incredible", "amazing", "elegant",
    "simply", "easily", "merely", "actually", "basically", "essentially",
    "arguably", "very", "extremely", "incredibly", "quite",
}

AMBIGUOUS = {"since", "while", "as per", "and/or"}

LATIN = {r"\be\.g\.", r"\bi\.e\.", r"\betc\.", r"\bvia\b", r"\bvs\.?\b"}

PASSIVE = re.compile(
    r"\b(is|are|was|were|be|been|being)\s+(\w+ed|done|made|used|sent|read|built|"
    r"written|found|held|kept|set|shown|given|taken|seen)\b", re.I)

PERFECT = re.compile(r"\b(has|have|had)\s+been\b|\b(has|have|had)\s+\w+ed\b", re.I)
PROGRESSIVE = re.compile(r"\b(is|are|was|were|be|been)\s+\w+ing\b", re.I)
CONTRACTION = re.compile(r"\b\w+'(s|t|re|ve|ll|d|m)\b", re.I)
# A noun cluster is 4+ consecutive words that are none of: articles, prepositions,
# conjunctions, pronouns, modals, or common verbs. Without a POS tagger this
# stopword screen is the workable approximation.
FUNCTION_WORDS = {
    "a", "an", "the", "this", "that", "these", "those", "and", "or", "but", "nor",
    "if", "then", "else", "so", "because", "although", "while", "when", "where",
    "of", "in", "on", "at", "to", "for", "with", "from", "by", "as", "into", "onto",
    "over", "under", "after", "before", "during", "between", "through", "about",
    "is", "are", "was", "were", "be", "been", "being", "am", "has", "have", "had",
    "do", "does", "did", "can", "will", "would", "should", "must", "may", "might",
    "not", "no", "it", "its", "you", "your", "we", "our", "they", "their", "he",
    "she", "his", "her", "i", "me", "my", "us", "them", "who", "which", "what",
    "all", "any", "each", "every", "some", "more", "most", "other", "such", "than",
    "use", "uses", "used", "make", "makes", "made", "see", "sees", "get", "gets",
    "set", "sets", "run", "runs", "add", "adds", "read", "reads", "write", "writes",
    "need", "needs", "want", "wants", "know", "knows", "click", "open", "close",
    "copy", "paste", "start", "stop", "check", "find", "show", "help", "let",
    "first", "next", "also", "only", "just", "very", "now", "here", "there",
}
WORD_RE = re.compile(r"[a-z][a-z'-]*")

INSTRUCTION_CAP = 20
DESCRIPTIVE_CAP = 25
PARAGRAPH_CAP = 6

CODE_FENCE = re.compile(r"```.*?```", re.S)
INLINE_CODE = re.compile(r"`[^`]*`")
URL = re.compile(r"https?://\S+")


class Finding:
    def __init__(self, line, rule, detail):
        self.line, self.rule, self.detail = line, rule, detail

    def __str__(self):
        return f"  {self.line:>5}  {self.rule:<18} {self.detail}"


def strip_code(text):
    """Blank out code so the linter does not grade identifiers."""
    text = CODE_FENCE.sub(lambda m: "\n" * m.group().count("\n"), text)
    text = INLINE_CODE.sub(" ", text)
    return URL.sub(" ", text)


def sentences(line):
    return [s.strip() for s in re.split(r"(?<=[.!?])\s+", line) if s.strip()]


def noun_clusters(line):
    """Yield runs of 4+ consecutive content words. Punctuation breaks a run."""
    for clause in re.split(r"[.,;:!?()\[\]\"]+", line.lower()):
        run = []
        for word in WORD_RE.findall(clause):
            if word in FUNCTION_WORDS:
                if len(run) >= 4:
                    yield " ".join(run)
                run = []
            else:
                run.append(word)
        if len(run) >= 4:
            yield " ".join(run)


LIST_MARKER = re.compile(r"^\s*(\d+[.)]|[-*+])\s+")


def blocks(lines):
    """Group prose into (start_line, text, is_list_item) blocks.

    A list item starts its own block so that its 20-word instruction cap is
    applied, and so the leading "1." does not read as a sentence boundary.
    """
    out, buf, start = [], [], 0
    listy = False

    def flush():
        if buf:
            out.append((start, " ".join(buf), listy))

    for n, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line or line.startswith(("#", ">", "|", "---", "```")):
            flush()
            buf.clear()
            continue
        if LIST_MARKER.match(line):
            flush()
            buf.clear()
            start, listy = n, True
            buf.append(LIST_MARKER.sub("", line))
        else:
            if not buf:
                start, listy = n, False
            buf.append(line)
    flush()
    return out


def lint(text, strict=False):
    findings = []
    clean = strip_code(text)
    lines = clean.split("\n")
    words_total = 0

    for n, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line or line.startswith(("#", ">", "|", "---")):
            continue

        low = line.lower()
        words_total += len(line.split())

        if ";" in line:
            findings.append(Finding(n, "semicolon", "use two sentences"))
        for m in CONTRACTION.finditer(line):
            findings.append(Finding(n, "contraction", m.group()))
        for m in PASSIVE.finditer(line):
            findings.append(Finding(n, "passive-voice", m.group()))
        for m in PERFECT.finditer(line):
            findings.append(Finding(n, "perfect-tense", m.group()))
        for m in PROGRESSIVE.finditer(line):
            findings.append(Finding(n, "progressive-tense", m.group()))
        for cluster in noun_clusters(line):
            findings.append(Finding(n, "noun-cluster", cluster))

        for word in re.findall(r"[a-z][a-z'-]+", low):
            if word in MARKETING:
                findings.append(Finding(n, "marketing-word", word))
            elif word in SUBSTITUTIONS and (strict or word not in ("verify", "require")):
                findings.append(
                    Finding(n, "word-choice", f"{word} -> {SUBSTITUTIONS[word]}"))
            elif word in AMBIGUOUS:
                findings.append(Finding(n, "ambiguous-word", word))

        for pat, better in PHRASES.items():
            if re.search(pat, low):
                findings.append(Finding(n, "phrase", f"-> {better}"))
        for pat in LATIN:
            if re.search(pat, low):
                findings.append(Finding(n, "latin-abbrev", "write it in English"))
        if re.search(r"\w+/\w+", line) and "and/or" not in low:
            pass  # paths and units are fine
        if "and/or" in low:
            findings.append(Finding(n, "slash", "write the words"))

    # Sentence and paragraph checks run on joined blocks, because one sentence
    # usually wraps across several source lines.
    for start, block, listy in blocks(lines):
        sents = sentences(block)
        for sent in sents:
            count = len(sent.split())
            cap = INSTRUCTION_CAP if (strict or listy) else DESCRIPTIVE_CAP
            if count > cap:
                findings.append(
                    Finding(start, "sentence-length",
                            f"{count} words (cap {cap}): {sent[:50]}..."))
        if not listy and len(sents) > PARAGRAPH_CAP:
            findings.append(
                Finding(start, "paragraph-length",
                        f"{len(sents)} sentences (cap {PARAGRAPH_CAP})"))

    return findings, words_total


def main():
    ap = argparse.ArgumentParser(description="Heuristic ASD-STE100 linter.")
    ap.add_argument("files", nargs="+", type=Path)
    ap.add_argument("--strict", action="store_true",
                    help="20-word cap on all sentences, full substitution checks")
    ap.add_argument("--quiet", action="store_true", help="print the score only")
    args = ap.parse_args()

    grand_findings = 0
    grand_words = 0
    missing = 0

    for path in args.files:
        if not path.exists():
            print(f"{path}: not found", file=sys.stderr)
            missing += 1
            continue
        findings, words = lint(path.read_text(encoding="utf-8"), strict=args.strict)
        grand_findings += len(findings)
        grand_words += words

        score = (len(findings) / words * 100) if words else 0.0
        print(f"\n{path}  —  {len(findings)} violations / {words} words  "
              f"=  {score:.2f} per 100 words")
        if findings and not args.quiet:
            print(f"  {'line':>5}  {'rule':<18} detail")
            for f in sorted(findings, key=lambda x: x.line):
                print(f)

    if len(args.files) > 1 and grand_words:
        total = grand_findings / grand_words * 100
        print(f"\nTOTAL  {grand_findings} violations / {grand_words} words  "
              f"=  {total:.2f} per 100 words")

    if missing:
        return 2
    return 1 if grand_findings else 0


if __name__ == "__main__":
    sys.exit(main())

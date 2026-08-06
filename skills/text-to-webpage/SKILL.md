---
name: text-to-webpage
description: "Rewrite user-provided raw UTF-8 text, transcripts, meeting notes, or Hebrew content into a complete, faithful, logically ordered, fine-grained RTL HTML webpage using the supplied reference visual shell. Use only when both conditions are met: the user explicitly requests turning text into a webpage or HTML, and the source text is pasted into the request or attached as a text-bearing file. Do not use for general HTML creation, reports or audits synthesized from other documents, web design, or requests that do not supply the source text."
---

# Structure Text as RTL HTML

## Mandatory Trigger Gate

Use this skill only when both of these conditions are satisfied:

1. The user explicitly asks to turn text into a webpage or HTML document.
2. The user pastes the source text or attaches a file containing the source text.

If either condition is missing, do not use this skill. If the user requests a text-to-webpage conversion without supplying the text, ask them to paste or attach it. Do not treat a request to create a report, audit, dashboard, landing page, or other webpage from independently gathered information as a trigger.

## Purpose

Rewrite the entire source into a clear, logically ordered Hebrew/RTL document. This is a full-content transformation, not a summary or overview. Preserve the exact visual and interaction shell from `assets/template.html`; change only the content inside `<main>` and, when appropriate, the page title.

## Content Rules

1. Read the source as UTF-8. If Hebrew appears as mojibake, reopen it with an explicit UTF-8 decoder before interpreting it.

2. Preserve every recoverable piece of information from the source:
   - facts, claims, qualifications, uncertainty, numbers, dates, examples, explanations, questions, answers, requests, objections, decisions, and follow-up items;
   - distinct repetitions when they add a new example, rationale, caveat, or speaker response;
   - small operational details, not just the main themes.

3. Do not summarize, compress into an overview, or omit content because it seems secondary. Rewrite speech into readable prose and order it by topic or chronology, but keep the full informational substance. Do not add a generated abstract, source disclaimer, meeting-closing sentence, or any other material that is not present in the source. Do not add conversational filler.

4. Avoid personal names. Remove names from speaker labels and prose, or replace them with role-based wording such as `המציגים`, `אחת המשתתפות`, `הצוות`, or `נציגת המשרד`, while retaining the surrounding meaning. Do not replace a removed name with a new specific name.

5. Do not invent, verify, or normalize disputed facts. Retain uncertainty and disagreement from the source in natural wording. If a passage is unclear, preserve the identifiable information and qualify only that passage; never use a generic disclaimer to excuse omitted content.

### Source authority, corrections, and coverage

- Treat the source transcript as the factual authority. The existing target page is a structural reference, never evidence for a source claim.
- Track each factual item with a status: `verified`, `unclear`, `user-corrected`, or `explicitly deleted`. Never infer missing OCR numerals, percentages, dates, or words from the target page, arithmetic, or context. If the user supplies a correction, apply it as an explicit override and use it consistently, but do not present it as a direct source quotation unless the source contains it.
- Before writing HTML, make an atomic coverage ledger, not only a topic list. Record each fact, qualification, number, date, example, explicit question, answer, objection, decision, operational detail, and follow-up item with its source location. For long sources, read and process the complete file in numbered chunks and carry one ledger forward.
- Maintain a deletion ledger for user-requested removals. Remove the requested sentence, paragraph, heading, or section exactly, and do not count an explicitly deleted item as a coverage failure. Renumber subsequent headings when a numbered section is removed.
- Check every ledger item off while drafting. After drafting, perform both audits: source → HTML (every item is present, user-corrected, or explicitly deleted) and HTML → source (every factual sentence maps to a source item or a user correction). Revisit any section that became conspicuously shorter because details were dropped.

6. Reorder by subject, not by speaking order. Group related statements, questions, examples, and answers under the same chapter even when they appeared far apart in the transcript. Use chronology only for timelines and ordered processes. Make the result read like a coherent document rather than a cleaned transcript.

7. Break the rewrite at the level of individual ideas:
   - Keep each paragraph focused on one claim, explanation, example, question, answer, or decision. Normally use one to three sentences per paragraph.
   - Split long source passages at topic changes, causal steps, examples, qualifications, and changes of speaker intent. Do not preserve a long transcript paragraph just because it was one source block.
   - Use one list item per independent fact. Use `<ol>` for an ordered process or sequence and `<ul>` for a set of parallel facts.
   - If a paragraph contains three or more distinct ideas, split it into multiple paragraphs, list items, or H3 subsections.

8. After factual validation, perform a natural-language pass. Prefer direct, flowing Hebrew such as `הדוגמאות כוללות...` and `אפשר לפנות...`. Avoid meta-introductions such as `דוגמאות שהוצגו`, `הוצעה גם אפשרות`, or `שנמסר במפגש` unless they are necessary to preserve meaning.

## HTML Structure and Tables

- Do not add a main-content `<h1>` title by default. Keep the page title in `<title>` only unless the user explicitly requests a visible heading. Do not follow the page title with a generated summary paragraph.
- Restore a chapter-first table of contents for long meeting documents. Use numbered direct-child `<h2>` elements for major chapters and numbered or unnumbered direct-child `<h3>` elements for their subtopics. For this source, use the original chapter logic as the preferred blueprint: the program frame; the first book; the second book; mathematical-sequence questions; practice scope and the teacher guide; book structure and teaching principles; angles; writing/drawing/support pages; heterogeneous and special education; the website and digital materials; transformations; applets and assessment; follow-up meetings and recordings; transition to the next grade; access, printed copies, and schedule; contact and support; and old books. Do not collapse this into a handful of mega-sections, and do not create dozens of tiny headings for every sentence.
- Make the table of contents useful, not merely decorative: use H3s for meaningful subtopics, sequences, question clusters, or decisions under the relevant H2. The bundled JavaScript uses these headings to build the sidebar.
- Use concise, specific H3 headings such as `ארבעת התחומים בתוכנית החדשה`, `התחום המספרי`, `התחום האלגברי`, and `הרצף בתוך התחום המספרי` when those are distinct source topics. Do not create empty headings or headings that merely repeat the paragraph below them.
- Use `<p>` for focused prose and `<ul>`/`<ol>` for complete grouped items. Use tables whenever the source presents comparable or repeated fields: books versus periods, domains versus hours, topics versus grades, actions versus effects, materials versus uses, channels versus purposes, or question categories versus answers. Put wide tables inside `.table-wrap`. Give every table a header row, keep each cell concise, and do not force long narrative or an ordered sequence into a table.
- Prefer a short introductory paragraph followed by a list when the source enumerates items. For example, present the four domains as four list items, then present the teaching sequence as an ordered list with one step per item. Do not render list-like content as four bold sentences inside one paragraph.
- Keep adjacent but different structures separate. For example, render `ארבעת התחומים בתוכנית החדשה` as its own H3 with a short explanation and four `<li>` items, then render `הרצף בתוך התחום המספרי` as a separate H3 with its own focused explanation and ordered list. Do not merge the enumeration and the sequence into one paragraph or one H3.
- Convert every explicit source question into a visible Q&A structure instead of narrating it as `נשאלה שאלה ...`: use `<div class="qa">` with a first paragraph labelled `שאלה:` and a following paragraph labelled `תשובה:`. Preserve the full question and answer. If the source has no answer, keep the question alone without inventing one. Use tables for a set of short, consistently shaped Q&As only when a table is clearer than separate `.qa` blocks.
- Use existing classes without adding CSS: `.qa` for source questions and answers, `.note` for source caveats, `.callout` for an important source-stated point, `.example` for examples, `.warning` for source-stated risks, `.tip` for source-stated advice, and `blockquote` only for a real quotation.
- Do not use `.lead`, `.meta`, `.source`, or a generic `.warning` merely to describe the source or the transformation. Use them only when their content comes from the source itself.
- Escape literal `<`, `>`, and `&` in prose; use HTML tags only for intended markup.

## Build and Validate

Create an HTML fragment containing only the intended contents of `<main>`, then run:

```powershell
python "<skill-dir>\scripts\build_html.py" `
  --template "<skill-dir>\assets\template.html" `
  --content "<content-fragment.html>" `
  --output "<output>\structured_text.html"
```

Use `--title "..."` only when the source-derived page title should differ from the template default. The helper must receive a fragment, never a complete HTML document.

Verify all of the following:

- the output is UTF-8 with `lang="he"` and `dir="rtl"`;
- there is exactly one `<html>`, `<head>`, `<body>`, and `<main>`;
- no placeholder remains and all HTML is well nested;
- every primary/secondary heading is a direct child of `<main>`;
- the content includes the full coverage map, with no generated overview, source note, names, or closing filler;
- every source-ledger item is present, explicitly user-corrected, or explicitly deleted; every factual HTML sentence maps back to a source item or user correction;
- the TOC follows a readable chapter-first hierarchy with meaningful H2/H3 subtopics, and no important cluster is buried in one oversized paragraph;
- explicit questions appear as `שאלה:`/`תשובה:` blocks rather than `נשאלה שאלה` narration;
- comparable repeated information uses concise tables where that improves scanning;
- search for every user-requested deletion and confirm it is absent; confirm every requested replacement value appears consistently; confirm numbered headings remain sequential after deletions;
- the template's `<style>`, sidebar, menu button, responsive rules, print rules, and navigation `<script>` remain unchanged.

The wording may differ from the source because it is being rewritten, but the informational coverage must not.

## Bundled Resources

- `assets/template.html` — the exact reusable visual shell derived from the supplied reference HTML.
- `scripts/build_html.py` — deterministic UTF-8 helper that replaces the template's `<main>` content and optionally updates `<title>`.

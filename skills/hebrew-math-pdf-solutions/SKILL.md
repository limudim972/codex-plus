---
name: hebrew-math-pdf-solutions
description: Create or revise polished Hebrew RTL HTML solution booklets from school mathematics PDFs, starting from a PDF alone when necessary. Use for solving selected or complete question ranges, choosing an appropriate school-level reasoning depth and method, extracting faithful OCR question text and printed answers, producing section-aware נתון/צ.ל./פתרון layouts, adding faithful drawings, writing all mathematics in Presentation MathML, and delivering A4 print pages with margins, right-side sidebar navigation, and verified rendering.
---

# Hebrew Math PDF Solutions

Build a complete, student-readable Hebrew solution booklet from the source PDF. Treat the PDF as the source of truth for the exact wording, diagrams, givens, subsection structure, and printed answers; solve independently and use the printed answers only for comparison.

The workflow must work from the PDF alone. Never depend on a previous HTML file, remembered question numbers, or assumptions about how another worksheet is organized. If an existing HTML artifact is supplied, inspect it first and preserve unrelated user changes, but rebuild any unreliable generated content from the PDF inventory.

## Durable user preferences

Apply these preferences unless the user explicitly overrides one of them:

- Produce a clean Hebrew RTL HTML booklet: the sidebar/TOC is on the right, navigation is separate from the page scroll, and navigation is hidden in print.
- Replace source question images with exact visible-PDF OCR. Do not paraphrase, summarize, correct, or add the visible prefix `נוסח השאלה (OCR):`; begin directly with the original wording.
- Place a faithful diagram immediately after the OCR question. A later subsection with new givens may receive an additional local diagram immediately after those givens.
- Use a normal detailed school-level solution: define unknowns, explain why equations follow, show intermediate algebra, handle both cases, and write the complete final answer.
- The solution must be detailed and fully reproducible by a student: define every unknown, explain the reason for each important step, show all necessary intermediate calculations and case splits, and state the complete final answer clearly. Do not jump from the givens to the result or replace derivations with phrases such as “solving the system” or “similarly.”
- Avoid vectors, trigonometry, and unexplained advanced methods. Prefer slopes, perpendicular slopes, distance formulas, systems, and elementary proportions.
- Prefer direct substitution into a given line equation when it is simpler than a slope-change calculation. For example, choose `x_A=5+t` and compute `y_A` by substituting into `y=3x-9`.
- Do not introduce notation the student has not learned, such as `Δx` or `Δy`, unless the user explicitly requests it. Use ordinary parameters and direct substitution instead.
- If the user requests particular parameter names, preserve them consistently throughout the solution. For example, use `t` for the first parameter and `s` for the second, rather than silently reverting to `a` or `b`.
- In coordinate-geometry diagrams, name the vertices with the user's preferred labels (such as `A,B,C,D,O`), show the relevant parameter visually when it represents a coordinate change, and write point coordinates with tight MathML subscripts such as `x_A,y_A` when requested.
- Do not add a separate theorem-justification callout when the problem statement already gives the relevant geometric fact and the callout does not advance the calculation. Keep only the reasoning needed to connect the constructed coordinates to the requested answer.
- If the user says not to use rotation, do not use rotation, a rotated-image argument, or equivalent transformation language in the visible proof. Replace it with congruence, equal angles, parallel lines, perpendicular lines, coordinates, similarity, area, or another elementary school-level argument.
- Before every visible solution, add a short Hebrew `מהלך הפתרון` block that previews the method and the order of the main ideas. Do not use coordinate-system setup merely as a default; when a synthetic school-level proof is available, prefer it.
- When the user requests the distance formula instead of Pythagoras, use the distance formula explicitly throughout the visible solution and do not silently switch back to Pythagoras.
- For circle centers, use a center such as `I(a,b)` when natural; for a circle tangent to both positive axes, state `r=a=b` and then use the direct distance formula to the remaining line.
- If a point divides a segment in a known ratio, use endpoint proportions (for example, points `K,L`) rather than vectors or an unexplained parameter.
- Use `x` as the parameter when it naturally represents an unknown x-coordinate. Use `y=mx+b` for visible line calculations and direct distance calculations; use `y=mx+n` only when the problem already uses `b` as a parameter.
- When the user asks for marking variables in a geometry proof, prefer `x` and `y` for the first two length variables instead of `s` and `u`. When angle measures are introduced as named quantities, use Greek labels such as `α` and `β` and define them before using them.
- Write all mathematics in valid Presentation MathML with `dir="ltr"`, explicit parentheses, non-stretching absolute-value bars, and structurally valid fractions, powers, and subscripts.
- For parallel-line relations, use a non-stretching inline fallback when the browser's MathML renderer stacks the symbol: `<span class="parallel-relation">FG&nbsp;∥&nbsp;BC</span>`. The CSS must set `display:inline-block`, `direction:ltr`, and `white-space:nowrap`; never use a stretchy `<mo>` for this relation. This fallback is allowed as a rendering exception to the general MathML rule.
- Keep block equations free of unwanted scrollbars with `.equation { overflow: visible; max-width: 100%; }`. Also keep compound inline MathML on one line with `.inline-math { white-space: nowrap; }`; CSS is only a safeguard, not a replacement for valid MathML structure.
- For every `<math>` element with more than one top-level mathematical child, wrap the complete expression in one outer `<mrow>`, including inline equalities, point lists, angle expressions, fraction sums, and displayed equations. Do not leave sibling `<mi>`, `<mo>`, `<mn>`, `<mfrac>`, or `<msup>` elements directly under `<math>`.

## Output contract

Produce a self-contained HTML file plus local drawing assets when needed. Inline SVG is acceptable for a reconstructed diagram when it keeps the file portable; whether the drawing is inline or external, keep it bounded by the question width and verify it visually.

- Set `<html lang="he" dir="rtl">` and write all explanatory prose in Hebrew.
- Create one question container for every requested question, in source order, with a stable generated id such as `q-{number}`. Do not hard-code a particular worksheet's question range into this skill.
- Put a faithful, exact OCR transcription of the complete original question at the start of its question container instead of displaying the source question image. Copy the wording from the visible PDF, not from memory or a summary: preserve singular/plural verbs, subsection letters, line breaks when meaningful, punctuation, parentheses, coordinate separators, signs, fractions, conditions, diagram references, and every requested result. Visually compare the finished OCR with the source image before finalizing; never paraphrase or silently improve the wording.
- Keep the OCR block itself clean: begin directly with the original question wording. Do not add a visible prefix such as `נוסח השאלה (OCR):`, an editorial title, or a summary before the transcription.
- Immediately after the OCR question text, include a clear faithful drawing whenever the question has a diagram or its geometry benefits from one. For a multipart question that introduces new givens in a later subsection, an additional local drawing may be placed immediately after that subsection's given text. Reconstruct the source diagram when necessary, clearly distinguishing given objects from objects constructed during the solution. Do not use the source question image as a substitute for the OCR text.
- Use the exact three labels `נתון`, `צ.ל.`, and `פתרון` as `h3` elements. Keep them visually consistent across all questions.
- Immediately before each solution section, include its own `<h3>מהלך הפתרון</h3>` followed by a concise Hebrew overview of that section's proof or calculation. For multipart questions, place a separate overview immediately after each subsection heading (for example, after `סעיף א` and after `סעיף ב`); never combine all subsection methods into one shared overview.
- Write the method overview as an ordered list with visible `1.`, `2.`, `3.` steps. In the solution, repeat the same step numbers in matching `.solution-step` blocks with a visibly different background, so the student can map every preview step to its detailed calculation.
- Repeat the actual wording of each method-list item in the matching solution-step heading, not only its number. Keep the order and numbering identical.
- Keep `נתון` and `צ.ל.` plain: no colored background, border, callout, or special card. A computed answer may be visually distinct; a PDF answer may be subtly distinguished only when it genuinely differs.
- Put every mathematical expression, including a single variable or coordinate, inside Presentation MathML with `dir="ltr"`, except for the explicitly permitted `.parallel-relation` rendering fallback. Do not use raw equation text, Unicode formula notation, LaTeX delimiters, or Markdown math elsewhere.
- Give every sentence its own paragraph or its own proof-table row. Put standalone equations in their own block. Do not hide several reasoning steps in one long paragraph.
- Make each question a separate A4 print page with real inner margins. Hide navigation and screen-only controls in print.
- Do not add an answer-key section unless the user explicitly asks for one.
- Show a printed PDF answer only when it is mathematically different from the computed answer. If it is equivalent, show the answer once and omit the PDF-answer block.

### Canonical reproducible document profile

Use this profile as the default output shape so a new thread can reproduce the same booklet without relying on an earlier HTML file:

- Keep the visible order inside each question as: `h1` question title, exact `.ocr-question`, `.question-drawing`, whole-question `נתון`, whole-question `צ.ל.`, then the relevant subsection(s) and solution blocks.
- Use `<div class="app-shell"><aside class="sidebar">…</aside><main class="pages">…</main></div>`. The sidebar is on the right, has its own vertical scroll, and contains links generated from the actual question ids. The pages region is a separate vertical scroll container.
- For every subsection, place `<h3>מהלך הפתרון</h3>` immediately before its solution and use an ordered list with visible `1.`, `2.`, `3.` numbering. For every list item, create a matching `<div class="solution-step">` in the same order. Its `.solution-step-title` must repeat the number and the exact wording of the list item, followed by the detailed calculation or proof. For a multipart question, give each subsection its own separate method list; never use one combined list for all subsections.
- Use a visibly different background for each `.solution-step`, while keeping `נתון`, `צ.ל.`, and the surrounding headings plain.
- When the user requests marking variables, use `x` and `y` for the first two geometric length variables, not `s` and `u`. For named angle measures, define and use Greek variables such as `α` and `β` instead of repeatedly introducing decimal angle labels.

Use this CSS baseline and tune only values that are necessary for the particular worksheet:

```css
@page { size: A4; margin: 16mm; }
:root { --ink:#173b68; --accent:#c65335; --paper:#f7faff; --line:#dbe5f2; }
* { box-sizing:border-box; }
html, body { margin:0; min-height:100%; background:#e9eef5; color:#182538; font-family:Arial,"Noto Sans Hebrew",sans-serif; }
body { direction:rtl; }
.app-shell { display:flex; flex-direction:row-reverse; direction:ltr; height:100vh; min-height:100vh; }
.sidebar { flex:0 0 210px; height:100vh; overflow-y:auto; scrollbar-gutter:stable; padding:22px 16px; background:var(--ink); color:#fff; direction:rtl; }
.sidebar h1 { margin:0 0 18px; font-size:1.1rem; }
.sidebar a { display:block; margin:7px 0; padding:9px 11px; border-radius:6px; color:#fff; text-decoration:none; background:#ffffff18; }
.sidebar a:hover, .sidebar a:focus { background:#ffffff38; }
.pages { flex:1; height:100vh; overflow-y:auto; scrollbar-gutter:stable; padding:24px; direction:rtl; }
.question { width:min(180mm,100%); min-height:265mm; margin:0 auto 24px; padding:11mm 12mm; background:#fff; box-shadow:0 2px 12px #173b6820; scroll-margin-top:1rem; page-break-after:always; break-after:page; }
.question:last-child { page-break-after:auto; break-after:auto; }
h1 { margin:0 0 10px; color:var(--ink); font-size:1.55rem; border-bottom:2px solid var(--line); padding-bottom:7px; }
h2 { margin:18px 0 8px; color:var(--ink); font-size:1.12rem; }
h3 { margin:17px 0 7px; color:var(--ink); font-size:1.04rem; }
p { margin:7px 0; line-height:1.58; }
.ocr-question { padding:12px 14px; border:1px solid #b7c9df; border-right:5px solid var(--accent); background:#fbfdff; line-height:1.7; }
.question-drawing { margin:12px auto 16px; padding:7px; border:1px solid var(--line); background:var(--paper); text-align:center; }
.question-drawing svg { display:block; width:min(100%,520px); height:auto; margin:auto; }
.equation { display:block; max-width:100%; margin:10px auto; overflow:visible; }
.inline-math { white-space:nowrap; }
.parallel-relation { display:inline-block; direction:ltr; white-space:nowrap; font-family:"Times New Roman",serif; font-style:normal; }
.method-steps { margin:8px 0 12px; padding:0 28px 0 0; }
.method-steps li { margin:5px 0; }
.solution-step { margin:12px 0; padding:10px 14px; border-right:5px solid #2d5f91; background:#f0f6fc; border-radius:5px; }
.solution-step-title { margin-bottom:6px; color:var(--ink); font-weight:700; font-size:1.02rem; }
.answer { margin:10px 0; padding:9px 12px; border-right:4px solid var(--accent); background:#fff4ef; }
.answer .parallel-relation { display:block; width:100%; text-align:left; font-size:1.25rem; }
.proof-table { width:100%; border-collapse:collapse; margin:10px 0; }
.proof-table th, .proof-table td { border:1px solid #c7d5e5; padding:7px; vertical-align:top; }
.proof-table th { color:var(--ink); background:#edf3fa; }
@media print {
  html, body { background:#fff; }
  .app-shell { display:block; height:auto; }
  .sidebar { display:none; }
  .pages { height:auto; overflow:visible; padding:0; }
  .question { width:auto; min-height:0; margin:0; padding:0; box-shadow:none; }
}
```

Use the CSS fallback for parallel relations because the browser can stack a MathML `∥` operator vertically even when `stretchy="false"` is present. Write relations such as `FG ∥ BC` as `<span class="parallel-relation">FG&nbsp;∥&nbsp;BC</span>`, especially in the final answer, and verify that the final answer is left-aligned. This is the intentional exception to the rule that mathematical content normally belongs inside MathML.

For a final answer that combines multiple fractions, always wrap all top-level children in one `<mrow>`. For example, use `<math class="equation" display="block" dir="ltr"><mrow><mfrac>…</mfrac><mo>+</mo><mfrac>…</mfrac><mo>=</mo><mn>1</mn></mrow></math>`. Do not put several sibling fractions and operators directly under `<math>`; that produces the broken stacked layout seen in question 62.

## End-to-end workflow

### 1. Establish scope and file locations

1. Identify the source PDF from the user message or workspace. If the user asks for “the rest,” determine the requested range from the visible worksheet and conversation context; do not invent a fixed range.
2. Identify or create an output directory beside the HTML, normally with an `assets/` subdirectory.
3. If an HTML file already exists, inspect its structure, assets, and scripts before editing. Preserve unrelated work, but do not keep duplicate or stale blocks merely because they are hidden by JavaScript.
4. Use the PDF skill and available local tools (`pdfinfo`, `pdftotext`, `pdftoppm`, `pdfplumber`, `pypdf`, or equivalent) to inspect the document. Use Python for extraction and verification when helpful; do not use OCR output as the sole source for equations or crop boundaries.

### 2. Render and inventory the PDF before solving

Render every relevant PDF page at a readable resolution and inspect the images visually. Text extraction helps locate candidates, but visual inspection is mandatory for fractions, signs, subscripts, diagrams, Hebrew punctuation, and page boundaries.

Create an inventory record for each requested question containing:

- question identifier and source page or pages;
- exact crop rectangle or crop rectangles;
- complete wording and every subsection label;
- whether data is stated for the entire question or only inside a subsection;
- the exact data belonging to each subsection;
- the exact requested result for each subsection;
- the printed PDF answer paired with that subsection, if present;
- unclear symbols, unreadable text, diagrams, or answer-key mapping that need a second visual check.

If a question crosses a page boundary, create one complete composite crop or clearly place multiple source images in the same question block. Never accept a crop that contains a fragment of the previous or next question, even if the text extraction seems correct. After creating or changing a crop, open the image and inspect its top, bottom, left, and right edges.

Use predictable asset names for reconstructed drawings, derived from the actual identifier, for example `q-{number}-diagram.svg`; never use a stale asset from a different question. Give every drawing a meaningful Hebrew `aria-label` or `alt` attribute.

### 3. Determine the Hebrew structure from the source

Use the question's actual information structure, not a fixed template applied blindly.

#### Data stated for the whole question

Use one question-level block:

```html
<h3>נתון</h3>
<p>Only the data stated in the question, without repeating the word “נתון” in the paragraph.</p>
<h3>צ.ל.</h3>
<p>The requested result, written directly.</p>
<h3>פתרון</h3>
<!-- solution steps -->
```

When the question has subsections, keep the whole-question `נתון` above them. For each subsection, add only its own `צ.ל.` and `פתרון` unless the subsection introduces additional data. If a subsection has additional source data, place a new plain `נתון` immediately before that subsection's `צ.ל.`; do not write `נתון לסעיף א:` or repeat the whole-question data.

#### No whole-question data; data belongs to subsections

Do not create a whole-question `נתון` block. For each subsection, use the same pattern:

```html
<div class="subsection-title">א.</div>
<h3>נתון</h3>
<p>Only the data printed for this subsection.</p>
<h3>צ.ל.</h3>
<p>The requested result for this subsection, written directly.</p>
<h3>פתרון</h3>
<!-- solution for this subsection -->
```

A subsection title may be a non-semantic styled label such as `א.` or `ב.`, but `נתון`, `צ.ל.`, and `פתרון` must remain `h3`. Do not use `צ.ל. — כלומר, צריך למצוא` or a heading containing “למצוא את”. Write the objective itself, for example “קודקודי המשולש” or “משוואות שני המעגלים”.

Do not repeat the word `נתון` inside the paragraph merely because the heading already says it. Do not copy a long “data from the question” paragraph into both `נתון` and `צ.ל.`. In the solution, it is fine and often necessary to refer to a source fact with “לפי הנתון בשאלה”; the restriction is on duplicating it in the `נתון` block, not on using it in reasoning.

### 4. Solve independently at the student's level

Solve every subsection before writing the final HTML prose. Use Python or a CAS only to verify algebra, systems, intersections, distances, radii, and numerical results; write the visible solution as a clear school-level derivation.

- Prefer elementary coordinate geometry, algebraic systems, midpoint and distance formulas, congruence, similarity, angle and circle theorems, and transformations appropriate to the worksheet level.
- Do not use vectors in the answer unless the question explicitly requires them.
- For coordinate-geometry solutions, do not use vectors or vector notation by default. Prefer slopes, perpendicular slopes, point-slope equations, distance formulas, and systems of equations.
- When finding a circle center in a coordinate-geometry problem, use center coordinates such as `I(a,b)` when that is the natural unknown. Relate the radius to the distances from the center to the axes or given lines, then solve the resulting equations visibly. For a circle tangent to both coordinate axes in the first quadrant, state explicitly that `r=a=b` before applying the direct distance formula to the remaining line.
- When a point divides a segment in a known ratio, prefer an elementary proportion using the endpoint names, such as `K` and `L`, instead of vectors or an unexplained parameter. If `P` divides `KL` with `KP:PL=u:v`, show the coordinate proportions explicitly: `x_P=(v x_K+u x_L)/(u+v)` and `y_P=(v y_K+u y_L)/(u+v)`. Use the problem's actual point names in the final solution; introduce `K` and `L` only as generic labels when needed.
- When a free coordinate is the natural parameter, use `x` (or the coordinate requested by the student) instead of introducing an unrelated parameter such as `a`; make clear that it denotes the relevant coordinate of the unknown point or center.
- Do not use trigonometry when an elementary geometric or algebraic argument is available; honor an explicit “no trigonometry” request throughout the whole booklet.
- Avoid unexplained advanced methods. If a method is unavoidable, introduce it in one short sentence and explain the quantities it uses.
- State the reason for every non-obvious deduction. A fact supplied by the question may be used in the solution with the reason `לפי הנתון בשאלה.`
- Never call a calculated coordinate, midpoint, angle, or length `נתון`; write `נמצא`, `מכאן`, or `לכן`.
- If a system is required, display the actual system before saying it was solved. Do not write only “פתרון המערכת”.
- Explain case splits at the intended level. For an absolute-value equation, show both sign branches and the algebra leading to each parameter value.
- Check final coordinates, radii, line equations, ratios, and geometric claims by substitution or by the defining condition.

Use line-equation notation consistently. In visible calculations, write non-vertical lines in the form `y=mx+b`; do not convert them to `Ax+By+C=0` merely to apply a distance formula. For a point `(x_0,y_0)`, use the direct distance formula to `y=mx+b`, `|y_0-mx_0-b|/sqrt(m^2+1)`. If `b` is already a problem parameter, use `y=mx+n` only where the notation would otherwise be ambiguous, and explain the choice briefly. Keep the final line answers in slope-intercept form whenever the question does not require another form.

Use parameters consistently. Prefer `t` for the first free parameter and `s` for a second independent parameter; use `u` only when `s` is already occupied or the source's notation makes it necessary. Do not switch letters mid-solution. Introduce parameters with a complete sentence, for example “נסמן את נקודת החיתוך ב־…”, so a bare “נסמן B” is not visually ambiguous. Keep point coordinates compact and explicit, such as `A(4,10)`, with the point name immediately next to its parentheses.

#### Choose the answer level and the method

Infer the instructional level from the PDF itself: inspect the surrounding exercises, section title, notation, previously introduced theorems, and the kinds of calculations expected. Use the lowest standard school level that solves the problem correctly. Do not turn a school exercise into an olympiad proof, a university derivation, or a computer-algebra transcript.

Use the following default ladder:

1. **Basic algebra and coordinate geometry:** substitute into line equations, find intersections, use slope, midpoint, distance, area, and a clearly displayed system.
2. **Standard Euclidean geometry:** use given angle facts, parallel-line angles, perpendicularity, Pythagoras, midpoint and segment theorems, congruence, similarity, and elementary circle theorems when they are part of the worksheet's level.
3. **Standard transformations:** use reflection, rotation, translation, or symmetry only when the diagram or the syllabus makes the transformation natural; explain what point or segment is mapped where.
4. **More advanced algebra only when necessary:** use a quadratic, discriminant, completing the square, or a parameter case split only after showing why it is needed and what each result means geometrically.

Use the smallest method that is both valid and teachable. Before writing the proof, state a short method plan and deliberately choose the fewest standard facts that reach the goal. Prefer a direct system over an unexplained formula, a midpoint or distance argument over vectors, and angle chasing or congruence over trigonometry when those methods are available. For elementary circle geometry, check the simple route in this order when applicable: equal arcs to equal chords, diameter or radius perpendicularity, cyclic-quadrilateral angle facts, similar or congruent triangles, and only then a longer angle chase. For tangent problems, begin with the radius-perpendicular-to-tangent fact; for right triangles, use Pythagoras or the explicitly requested distance formula. Do not add a transformation, rotation, coordinate setup, auxiliary variable, or proof table unless it makes the argument shorter or clearer. Do not use vectors, trigonometry, matrices, determinants, calculus, or a CAS-generated argument unless the question explicitly requires that tool or no appropriate elementary method exists. A Python/CAS calculation may verify the work privately, but it must not replace the visible school-level reasoning.

When adding a diagram, draw each geometric object exactly once. Do not redraw a side, tangent, diagonal, or boundary as a second overlapping shape. Check that the visual relationships stated in the solution are geometrically exact: tangent lines touch the circle, radii meet tangent lines perpendicularly, a diameter passes through the center, a chord meets the stated line at the labeled intersection, and a circumscribed square has one coherent set of four sides rather than an accidental second square. Keep auxiliary proof lines visually distinct from givens, and do not invent a point or relation that is absent from the source. Put point labels just outside strokes with enough offset to prevent overlap; put labels for given lines and conditions directly beside or above the corresponding line, with enough spacing that the label cannot be mistaken for a second geometric object; for example, place a label such as `x=-b` above or immediately beside its vertical dashed line.

Default to a **normal detailed student solution**:

- show the definitions and intermediate values needed to reproduce the result;
- give a short reason before or beside every important equation;
- show the actual algebra in systems and case splits, not only the final parameter;
- explain why an algebraic solution is accepted or rejected by the geometry or domain;
- finish with a clear answer in the requested notation.
- When the user asks for a solution or more detail, provide the complete derivation from the given data to the final answer: define unknowns, show intermediate substitutions and simplifications, display both branches of absolute-value or case-split equations, compute every requested coordinate/length/radius, and write the final result explicitly. Do not replace these steps with phrases such as “solving the system” or “similarly.”
- Match the desired school level shown by a clear center-parameter solution: define the center, explain why each radius or distance equation follows, write the distance formula, simplify one algebraic step at a time, and finish with the requested coordinates or equation. Keep the reasoning complete but avoid unnecessary advanced machinery.
- Use `x` as the parameter when it makes mathematical sense, especially when it represents the x-coordinate of an unknown point or center. If the user explicitly requests another notation, apply that notation consistently throughout the visible solution, including the definition of the unknown, substitutions, case split, and final answer.

Use a shorter solution only when the step is immediate and already established. Add more detail when a student could reasonably ask “why does this equation follow?” or “what does this result give us?”. For a proof, prefer a `טענה`/`נימוק` table so each conclusion and its justification can be checked independently. The finished answer should be rigorous enough for marking, but readable enough for a student to learn the method from it.

Before finalizing each subsection, perform this level check:

- Could a student who knows the material shown in the PDF reproduce every line without guessing a missing theorem?
- Is every advanced-looking symbol or method necessary and explained?
- Are the visible tools simpler than, or at least no more advanced than, the surrounding exercises?
- Are all computational shortcuts hidden in verification rather than presented as reasoning?

### 5. Use tables where they improve mathematical clarity

For geometry, convert a multi-step proof into a two-column table whenever the argument contains several linked claims, angle chasing, midpoint reasoning, congruence, similarity, a transformation, or a chain of equalities. Use the headings `טענה` and `נימוק`.

```html
<table class="proof-table" dir="rtl">
  <thead>
    <tr><th>טענה</th><th>נימוק</th></tr>
  </thead>
  <tbody>
    <tr>
      <td><!-- MathML and short claim --></td>
      <td>הנתון בשאלה.</td>
    </tr>
    <tr>
      <td><!-- next claim --></td>
      <td><!-- theorem or deduction --></td>
    </tr>
  </tbody>
</table>
```

Put one logical statement per row. Keep each reason concrete: name the given fact, theorem, congruence criterion, parallel-line angle fact, midpoint fact, or algebraic operation. Do not place a long paragraph before the table explaining that the explanation is being converted to a table. Use ordinary prose and equations for a short one- or two-step calculation. Use a table for parameter cases, solution counts, or other repeated exact pairings when that is clearer than stacked lines.

### 6. Write all mathematics as robust Presentation MathML

Every `<math>` element must have `dir="ltr"`.

- Use `display="block"` for standalone equations and `class="inline-math"` for mathematics inside prose.
- Use explicit `mo` punctuation for parentheses. Do not use plain `<mfenced>` for parentheses because it is inconsistently rendered in browsers. Write `<mo>(</mo>` and `<mo>)</mo>` inside the appropriate `mrow`.
- Prefer explicit non-stretching `mo` bars for absolute values: `<mo stretchy="false">|</mo><mrow>...</mrow><mo stretchy="false">|</mo>`. The `stretchy="false"` attribute is required so a bar does not become excessively tall when rendered beside a fraction or square root.
- Use `<mi>` for variables and point names, `<mn>` for numbers, and `<mo>` for operators, punctuation, relations, degrees, and signs.
- Use `<mfrac>`, `<msup>`, `<msub>`, `<msqrt>`, `<mover>`, `<mrow>`, and `<mtable>` structurally. For tight labels use `<msub><mi>X</mi><mi>P</mi></msub>` or `<msub><mi>O</mi><mn>1</mn></msub>`, never Unicode subscripts.
- For coordinates, keep the point name directly next to explicit parentheses. For example:

```html
<math class="inline-math" dir="ltr">
  <mrow>
    <mi>A</mi><mo>(</mo><mn>4</mn><mo>,</mo><mn>10</mn><mo>)</mo>
  </mrow>
</math>
```

- Use `<mtable>` inside MathML for a displayed system, not an HTML table pretending to be an equation.
- Escape `<` and `>` as `&lt;` and `&gt;` when they occur in HTML source, or use the corresponding MathML operator safely.
- Keep Hebrew explanations outside MathML. Avoid `<mtext>` unless the text is genuinely part of the mathematical notation.
- Do not leave mathematical symbols in prose, image captions, headings, answer labels, or table cells outside MathML. Put the prose and the MathML next to each other instead.
- Inspect the rendered page after any bulk MathML rewrite. In particular, verify parentheses, absolute-value bars, fractions, roots, powers, and tight subscripts visually.

### 7. Compare computed answers with the printed PDF answers

Map answers by question and subsection, not by proximity alone. Answer keys may be printed after several questions, in a separate column, or at the end of the PDF. Verify the mapping visually and keep the source ordering and notation when displaying a real discrepancy.

Normalize only harmless equivalent notation when deciding whether answers match. Examples include reordered equivalent circle equations or a different order of two already-proven alternatives. Check centers, radii, signs, domains, point labels, and conditions before declaring two answers equivalent.

Use this policy:

1. Show the computed answer first.
2. If the PDF answer is mathematically identical, do not show a PDF-answer block.
3. If the PDF answer is genuinely different, show `תשובת ה־PDF:` immediately below the computed answer and state exactly what differs.
4. If the PDF contains no printed answer for that subsection, do not invent one.
5. Never emit duplicate PDF answers, including a hidden static block plus a dynamic replacement. Make the source DOM authoritative; if JavaScript is used, it may enhance navigation but must not be relied upon to hide stale visible answer blocks.

### 8. Build the HTML and screen navigation

Keep the document self-contained except for local assets. The visible page content must consist only of the navigation UI and question containers. Do not place an explanatory paragraph, table, answer key, or leftover solution before the first question container.

Use a fixed or sticky sidebar on the right side of the screen, because the document is Hebrew RTL, with links generated from the actual question inventory. Give the sidebar its own `overflow-y: auto` scroll container. Give the pages area its own `overflow-y: auto` scroll container and a fixed viewport height; do not let the browser body become the only page scroller. Keep the two scrollbars separate and inspect their positions in the in-app browser. Use `scrollbar-gutter: stable` and `scroll-margin-top` for predictable jumps. Keep the Hebrew content `dir="rtl"` while using an outer layout direction that places the sidebar on the right and keeps the pages readable.

Use a structure equivalent to:

```html
<div class="app-shell">
  <aside class="sidebar" aria-label="ניווט בין השאלות">
    <!-- generated question links -->
  </aside>
  <main class="pages">
    <section class="question" id="q-{number}">
      <!-- faithful OCR transcription, then the drawing and solution structure -->
    </section>
  </main>
</div>
```

The `{number}` placeholder is illustrative only; replace it from the discovered inventory. Do not leave placeholder text in the final file. Keep the sidebar hidden in print.

### 9. Enforce A4 print layout and real margins

Use a print-safe baseline and adjust it after rendering:

```css
@page { size: A4; margin: 18mm 16mm 18mm; }

.question {
  box-sizing: border-box;
  width: 180mm;
  min-height: 265mm;
  margin: 0 auto 12mm;
  padding: 10mm 10mm 12mm;
  page-break-after: always;
  break-after: page;
  scroll-margin-top: 1rem;
}

@media print {
  .sidebar, .screen-only { display: none !important; }
  .pages { height: auto; overflow: visible; margin: 0; padding: 0; }
  .question {
    width: auto;
    min-height: 0;
    margin: 0;
    padding: 10mm 10mm 12mm;
  }
}
```

For displayed MathML equations, use this baseline so fitting equations do not acquire unnecessary scrollbars:

```css
.equation {
  display: block;
  max-width: 100%;
  margin: 10px auto;
  overflow: visible;
}
```

Do not use `overflow-x: auto` on `.equation`. If an unusually long expression needs a different responsive treatment, simplify or reflow the source equation first and verify the rendered result.

The exact values may be tuned for the worksheet, but preserve both the `@page` margin and the inner `.question` padding. An outer margin alone is not sufficient. Bound any local drawing asset with `max-width: 100%`, `height: auto`, and `object-fit: contain`; never allow a drawing to force its solution off the printed page without checking the result.

### 10. Verify the finished artifact

Run structural checks, then visual checks. At minimum:

1. Parse the HTML and, if it contains a script, compile the script with Node or an equivalent syntax check.
2. Confirm that every discovered question appears exactly once, in the requested order, and that every referenced image exists.
3. Confirm that the first visible content in the pages area is the first question's OCR transcription; no old notes, tables, solution fragments, answer key, or drawing from another question may precede it.
4. Confirm each question begins with word-for-word OCR checked against the source image, places the correct drawing immediately afterward (and any permitted subsection drawing after its new givens), and contains the correct `נתון`/`צ.ל.`/`פתרון` structure for its actual data scope.
5. Confirm every mathematical item is inside `<math dir="ltr">` except the deliberate `.parallel-relation` fallback, MathML tags are balanced, and no plain `<mfenced>` remains for parentheses. Search for raw fractions, equation chains, LaTeX delimiters, Unicode superscripts/subscripts, and loose mathematical comparisons.
6. Confirm parentheses render as explicit `<mo>(</mo>` and `<mo>)</mo>`, absolute values render with visible bars, and subscripts remain tight through `msub`.
7. Confirm proof tables have `טענה`/`נימוק` headers, one logical claim per row, and no geometry proof that should be a table is left as an unreadable paragraph.
8. Confirm computed/PDF answers are paired by subsection, unchanged PDF answers are omitted, and every retained PDF answer includes the exact stated difference.
9. Confirm `@page` is A4, inner page margins are visible, every question begins on a new print page, and the sidebar is hidden when printing.
10. Serve the output directory over HTTP, for example with `python -m http.server 8765 --bind 127.0.0.1`, and open `http://127.0.0.1:8765/<file>.html` in the in-app browser. Prefer the HTTP preview over `file://`, because the browser may block local-file navigation or retain a stale file tab. Inspect representative early, middle, and late questions, plus every changed OCR block, drawing, fraction layout, parallel relation, and final answer. Use the browser skill for local-page inspection; do not substitute direct Playwright control when the browser skill is available.
11. In the live preview, verify concrete layout signals rather than relying only on appearance: `document.documentElement.scrollWidth === document.documentElement.clientWidth`, `document.body.scrollWidth === document.body.clientWidth`, every `.equation` has `scrollWidth <= clientWidth`, the sidebar and pages each have their own vertical scroll container, and the browser console has no errors. Check a screenshot at the top of each changed question and after jumping through the sidebar links.
12. Render the HTML to PDF or print preview when possible and inspect page images for clipping, overflow, broken RTL order, missing parentheses, missing diagrams, duplicated blocks, and incorrect page breaks. If any visual issue appears, fix the source and recheck the entire affected question.

## Common failure modes to prevent

- OCR contains text from the previous or next question, or drops a sign/fraction: re-render, visually compare with the PDF, and correct the transcription from visible boundaries.
- A subsection's data is placed in a whole-question `נתון`: move it to that subsection and remove the whole-question block.
- `נתון`, `צ.ל.`, or `פתרון` is duplicated or styled differently: normalize all three to the same `h3` pattern.
- The goal says “למצוא את” or “צ.ל. — כלומר…”: replace it with the requested object itself under plain `צ.ל.`.
- A calculated result is called “נתון”: label it as a result or deduction.
- A given is used without a reason: write `לפי הנתון בשאלה` in the solution, without duplicating it in the given block.
- Parentheses disappear: replace `mfenced` parentheses with explicit MathML `mo` nodes and re-render.
- `X_P` or `O_1` is visually loose: use `msub` with the base and subscript as adjacent MathML nodes.
- A geometric proof is hard to scan: convert its logical chain to a `טענה`/`נימוק` table.
- Vectors or trigonometry make a school-level solution opaque: replace them with the simplest valid elementary method unless explicitly required.
- The solution is only an answer key or jumps over essential algebra: add the missing definitions, intermediate equations, and reasons.
- The solution is much more advanced than the worksheet: infer the surrounding level again and replace the method with the simplest syllabus-appropriate one.
- The same PDF answer appears twice: remove unchanged PDF blocks from the source DOM and retain only genuine discrepancies.
- The method preview has numbers but the detailed proof has only numbers: repeat the exact text of every method-list item in its matching `.solution-step-title`, and verify the list-item count equals the solution-step count for every subsection.
- `FG ∥ BC` still appears vertically stacked: remove the relation from MathML and use the `.parallel-relation` inline-block fallback; for a final answer, set it to `display:block; width:100%; text-align:left`.
- A sum of fractions breaks into separate vertical columns: wrap the entire equation in a single outer `mrow`, including every fraction, operator, equality sign, and final number.
- An inline equality, point list, angle, or coordinate expression renders with unexpected spacing or a scrollbar: wrap all of its top-level MathML children in one outer `mrow`; do not rely on `stretchy="false"` or `overflow: visible` to repair malformed structure.
- The solution works but is unnecessarily complicated: return to the method preview, remove rotations, vectors, extra coordinates, and auxiliary variables, and replace them with the shortest valid school-level fact sequence.
- A reconstructed circle diagram looks plausible but contradicts the proof: verify each point's membership, each intersection, each perpendicular/tangent relation, and each parallel relation against the source before keeping the drawing.
- A geometry proof reuses generic `s` and `u` after the user requested marking variables: rename the first two lengths consistently to `x` and `y`, including definitions, substitutions, headings, and the final answer; use `α` and `β` consistently for named angles.
- A page begins with leftover text: ensure all global content is outside the pages flow or remove it; the first page-flow child must be the first question.
- Screen scrolling moves the entire body or combines the sidebar and pages scrollbar: make both regions independent scroll containers and verify their placement visually.

## Final handoff

Report the absolute path to the generated HTML and mention only material changes and verification results. Note any unresolved ambiguity in the PDF. Do not paste the full HTML into the final response.

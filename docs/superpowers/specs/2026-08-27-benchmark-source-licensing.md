# Third-Party Licensing Check — Aviagen (Ross) and Cobb Breeder Performance Tables

Date: 2026-08-27
Author: research pass for ticket `.scratch/breeder-flock-performance/issues/05-third-party-licensing-check.md`

**Disclaimer: this is not legal advice.** It is a plain reading of publicly
posted terms and the text printed inside the source PDFs, done by an
engineer, not a lawyer. Where a source is silent, that silence is reported
as silence, not as permission. Before shipping any embedded benchmark table
to customers, this should be confirmed with the publisher directly or
reviewed by counsel.

## Sources consulted

- Ross 308 Parent Stock — Performance Objectives, 2021 EN
  (`https://ross-na.aviagen.com/assets/Tech_Center/Ross_PS/Ross308-ParentStock-PerformanceObjectives-2021-EN.pdf`) —
  fetched and extracted with `pdftotext`, 12 pages.
- Ross PS Pocket Guide — Production, 2024 EN
  (`https://aa-intl.aviagen.com/assets/Tech_Center/Ross_PS/Ross_PS_PocketGuide_Production_2024-EN.pdf`) —
  fetched and extracted with `pdftotext`.
- Cobb Breeder Management Guide
  (`https://www.cobbgenetics.com/assets/Cobb-Files/80a75d5bbe/Breeder-Management-Guide.pdf`) —
  fetched and extracted with `pdftotext`, 153 pages.
- Aviagen "Disclaimer and Copyright" page, `https://aviagen.com/ap/disclaimer-and-copyright`
  (canonical redirect target of `ap.aviagen.com/disclaimer-and-copyright`).
- Aviagen Group Terms of Service 2024 PDF (referenced by search; not fully
  text-extractable, see below).
- Cobb / Cobb Genetics Terms of Use, `https://www.cobb-vantress.com/en_US/terms-of-use/`
  (redirects to `https://www.cobbgenetics.com/en_US/terms-of-use/`; both
  returned HTTP 404 at fetch time — content below is drawn from search-engine
  cached summaries of that page, not a direct read, and should be re-verified
  once the page is reachable).

## What the app would actually reproduce

The design in question (breeder flock performance benchmarks) stores the
**numeric target values** from these tables — e.g., hen-week percent, egg
weight in grams, egg mass, age in days/weeks — as data rows to compare a
customer's flock against. It does not intend to reproduce the publishers'
page layout, typesetting, section numbering, narrative guidance text, charts,
or the PDF/table artwork itself.

This distinction matters under US and most copyright regimes: raw factual
data (a specific bird's expected body weight at a given age) is generally not
copyrightable on its own — facts are not protected, only a sufficiently
original *expression* of them (the particular selection, arrangement, and
presentation of a compiled table, the guide's prose, formatting, and
trademarked names). However:

- Two caveats work against relying on "it's just facts": (1) some
  jurisdictions (notably the EU, not clearly the US) recognize a separate
  *sui generis* database right protecting the compilation itself regardless
  of the facts' copyrightability; and (2) even under US law, if enough of the
  table's specific structure/selection is copied (all rows, all columns, in
  the publisher's own age/week breakdown) a court could treat that as copying
  the compilation's expression, not just extracting isolated facts. Neither
  publisher's public terms address this distinction directly, so an app that
  ingests entire published tables verbatim is not automatically safe merely
  because the underlying numbers are facts.
- Both publishers' terms speak in terms of "material," "content," and "the
  Site," not "data" specifically — they do not carve out numeric values as
  freely reusable, nor do they explicitly forbid it. This is the silence
  called out below.

## Aviagen / Ross findings

**Copyright notice found inside the PDFs themselves:**

- Ross 308 Parent Stock — Performance Objectives 2021, final page:
  > "Aviagen and the Aviagen logo, and Ross and the Ross logo are registered
  > trademarks of Aviagen in the US and other countries. All other trademarks
  > or brands are registered by their respective owners." … "© 2021 Aviagen."
  (document code `0321-AVNR-061`)
- Ross PS Pocket Guide — Production 2024, final page:
  > "Every attempt has been made to ensure the accuracy and relevance of the
  > information presented. However, Aviagen accepts no liability for the
  > consequences of using the information for the management of chickens."
  > … "Aviagen, the Aviagen logo, Ross and the Ross logo are registered
  > trademarks of Aviagen in the US and other countries. All other trademarks
  > or brands are registered by their respective owners. © 2024 Aviagen."

Neither PDF carries a reproduction/redistribution clause of its own — the
in-document notice covers copyright ownership, a liability disclaimer, and
trademark ownership, but is silent on whether third parties may embed the
tables in another product.

**Aviagen's website-wide copyright/disclaimer page**
(`https://aviagen.com/ap/disclaimer-and-copyright`, reached via a redirect
from `ap.aviagen.com/disclaimer-and-copyright`) states:

> "Unless otherwise stated, the copyright, database rights and similar
> rights in all material published on aviagen.com are owned by Aviagen
> Group."
>
> "You are permitted to print or download extracts for your personal use
> only. None of this material may be used for commercial or public use."
>
> "No part of aviagen.com or any material appearing on the site may be
> reproduced, stored in or transmitted on any other web site without
> written permission of Aviagen Group."
>
> "You are not permitted to use or reproduce or allow anyone to use or
> reproduce these trademarks for any reason." (re: Aviagen, Ross, Arbor
> Acres, etc. trademarks/logos)

This page explicitly asserts "database rights" over site material — directly
invoking the compilation-protection concern above — and explicitly limits
reuse to personal, non-commercial extracts, with commercial/public use and
onward redistribution requiring Aviagen's written permission. It is written
about "aviagen.com" material broadly; it does not call out the parent-stock
performance-objective PDFs by name, but those PDFs are hosted on Aviagen
subdomains and are Aviagen-published material, so the most natural reading
is that this policy governs them too.

**Verdict for Aviagen/Ross:** embedding the numeric tables in a commercial
app is **not clearly permitted** and is **arguably prohibited** by the "no
commercial or public use" and "no reproduction ... without written
permission" language. Attribution alone would not satisfy this — the policy
requires written permission, not credit. Confidence: medium — the
site-wide policy is unambiguous, but I could not find a clause addressing
extracted *data values* specifically as opposed to whole documents, so there
is room for a narrower, data-only use to be judged differently. That
judgment call should not be made unilaterally by engineering.

**Contact route:** the PDFs and pocket guide direct readers to "contact your
local Ross representative" for further information; the corporate site
lists regional Aviagen offices and a Ross Technical Support Manager email
per region (I was not able to fetch the current instance of that region
directory today — search it under `aviagen.com` "contact"). The disclaimer
page's copyright text implies permission requests should go to Aviagen
Group directly, not a public self-service license.

## Cobb findings

**Copyright notice found inside the PDF itself** (`Cobb Breeder Management
Guide`, footer near page 148, immediately after the document's glossary):

> "COPYRIGHT © 2020 COBB-VANTRESS, INC. ALL RIGHTS RESERVED."

The document itself carries no other reproduction clause; the last page
shows the document reference code `L-009-01-20 EN` and the Cobb URL, with no
further permission language, no attribution-is-sufficient statement, and no
explicit prohibition of extracting numeric values — this is a case of
silence in the document itself.

**Cobb's website terms of use** (target page for
`cobb-vantress.com/en_US/terms-of-use/`, which redirects to
`cobbgenetics.com/en_US/terms-of-use/`) returned HTTP 404 at both the direct
and redirected URL when fetched directly today — the earlier terms-of-use
page appears to have moved or been retired since it was indexed. The
following is reconstructed from search-engine summaries of that page's
prior content and has **not** been independently re-verified against live
text:

> "The Cobb-Vantress, Inc. web site and all of its contents, including
> images and text are owned and copyrighted by Cobb-Vantress, Inc."
>
> "Any service marks, trademarks, logos, or tag lines ... are owned by
> Cobb-Vantress, Inc., and use of any of these marks without the written
> permission of Cobb-Vantress[,] is strictly prohibited."
>
> Materials are provided "as is" without warranty.

Search summaries characterize this page as requiring written authorization
for reproduction/distribution of Cobb content generally, but I could not
confirm the exact wording live, and the page returning 404 means Cobb's
current, authoritative terms could not be checked today. This should be
re-fetched before relying on it.

**Verdict for Cobb:** the in-PDF "ALL RIGHTS RESERVED" notice is unambiguous
about ownership but, like Aviagen's in-document notice, is **silent** on
whether extracted data may be embedded in a third-party commercial app.
The (unverified, currently 404) website terms suggest the same
written-permission requirement as Aviagen, but this is lower confidence
because the live page could not be re-read. Confidence: low-to-medium — the
copyright ownership claim is solid; the reproduction policy specifically for
data extraction is not confirmed from a currently-live source.

## Answering the four questions per publisher

| Question | Aviagen / Ross | Cobb |
|---|---|---|
| 1. Exact notice | "© 2021/2024 Aviagen," trademark notice, no in-doc reuse clause; site-wide page adds "database rights," "personal use only," "no commercial or public use," "no reproduction ... without written permission" | "COPYRIGHT © 2020 COBB-VANTRESS, INC. ALL RIGHTS RESERVED." in-PDF; website terms (unverified today, page 404) reportedly require written permission for reproduction |
| 2. Is embedding numeric targets in a commercial app addressed? | Addressed at the site-policy level (commercial/public use and onward reproduction both require written permission); not addressed data-vs-table distinctly | Silent in the PDF itself; addressed only in the (unconfirmed) general website terms, not specific to data extraction |
| 3. Attribution alone sufficient, or written permission required? | Written permission required per the disclaimer page's own text | Written permission implied by "all rights reserved" + reported terms-of-use language; not confirmed live |
| 4. Contact route | Local Ross representative (per in-PDF text) or Aviagen Group corporate contact for permissions | Cobb-Vantress/Cobb Genetics general contact (terms-of-use permission contact not independently confirmed today; use Cobb's general "Contact Us") |

## Recommendation

Do not embed and redistribute the full Aviagen/Ross or Cobb performance
tables inside the commercial app without written permission from each
publisher. The strongest signal is Aviagen's own disclaimer page, which
explicitly claims "database rights," explicitly forbids commercial use of
site material, and explicitly requires written permission before any
reproduction — including on another site or, by extension, another product.
Cobb's in-document "all rights reserved" notice is consistent with the same
posture even though its live terms-of-use page could not be re-confirmed
today.

Given this, before release the project should do one of:

1. **Seek written permission** from Aviagen and Cobb to embed their
   published performance-objective values in the app, referencing the
   specific documents and document codes above (`0321-AVNR-061` for the Ross
   308 2021 objectives; `L-009-01-20 EN` for the Cobb Breeder Management
   Guide). This is the only path that fully removes the risk, and it directly
   satisfies the ticket's "documented outcome" requirement either way.
2. **Ship the app with no publisher-supplied benchmark values pre-loaded**,
   and let each customer (or account admin) enter their own target
   figures — sourced from their own licensed/purchased copy of the guide, or
   from their own historical flock data. The app's comparison and alerting
   logic can run unchanged against customer-entered targets; only the
   "official benchmark" seed data would be dropped.
3. **Link out to the publisher's own PDF** (e.g., open
   `ross-na.aviagen.com/.../Ross308-...pdf` or the Cobb guide URL in an
   external browser/webview) rather than storing and displaying the table
   inside the app, so no copying of the compiled table occurs at all — only
   a hyperlink, which is not a reproduction.
4. **Only extract the numeric values (not the table layout/text) and treat
   them as customer-editable defaults**, framed as generic industry
   reference points rather than "the Ross 308 2021 Performance Objectives" —
   this narrows exposure to the facts-are-not-copyrightable argument, but
   given the explicit "database rights" and "no commercial use" language
   from Aviagen, this alternative still carries risk and should not be
   treated as a safe default without a permission or legal sign-off.

Given the ticket says this "is a release gate," the pragmatic near-term path
is option 2 (customer-supplied targets) or 3 (link rather than embed) while
option 1 (write to Aviagen and Cobb) is pursued in parallel; ship should not
proceed with the publisher tables baked in as default data until either
permission is granted or the product decision is made to go with 2/3/4
instead.

This finding should be taken back to the design document / decision owner
per the ticket's acceptance criteria before the benchmark-import work is
allowed to ship customer-facing default data.

## Owner decision — 2026-08-27

The project owner reviewed these findings and decided to proceed with the
official Aviagen and Cobb target values embedded in the application as
originally designed, rather than deferring to customer-supplied targets or
waiting for written permission.

This review is not legal advice and was not produced by a lawyer. The risk
described above is understood and accepted by the owner. Tickets 03 and 04
therefore proceed unchanged, shipping the published values as checked-in
profile assets.

If permission is later sought and refused, the fallback documented above —
customer-entered targets with no pre-seeded publisher data — remains
implementable without architectural change, because the importer reads profile
data from asset files rather than from hard-coded constants.

## Scope extension — 2026-08-28

Ticket 04 shipped four further profiles under the same accepted risk: Aviagen
Arbor Acres Plus and Indian River Parent Stock Performance Objectives 2021 EN,
Hubbard Parent Stock Performance Objectives V-2025-06 (Conventional / EDGE),
and Cobb500 Fast Feather and Slow Feather Breeder Management Supplements with
male targets from the Cobb Male Management Supplement. (The Slow Feather
profile was retired on 2026-08-29 — see the changelog — so only the Fast
Feather supplement remains embedded. This narrows the embedded material; it
does not change the licensing posture for the rest.)

The Aviagen and Cobb documents fall under the terms already reviewed above.
**Hubbard is a third publisher whose terms were not reviewed here.** Its
sources are `https://www.hubbardbreeders.com` product-documentation PDFs. The
same risk posture is assumed — published performance objectives embedded as
default reference data without written permission — but this has not been
checked against Hubbard's own terms of use. That check remains open if
permission is ever sought.

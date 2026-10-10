# Independent reviews

Each review was made by a reviewer who had not done the work under review, told to check the claims against the
1988 User's Guide and by running simulations, and not to trust the project's own documentation. Findings and how
each was dealt with are summarised in `docs/accuracy_evidence.md`, section 7.

| Report | What was reviewed |
|---|---|
| REVIEW_ee26d33.md | the first cycle-accuracy model and timing bench |
| REVIEW_2.md | the FILL/PIXBLT engines and their timing |
| REVIEW_3.md | timing closure before the NARC final patch |
| REVIEW_4.md | the drop-in survey and audit |
| REVIEW_5.md | the drop-in timing steps (found the write-path issue fixed in 8b483e8) |
| REVIEW_6.md | the fix for REVIEW_5 (8b483e8) |
| REVIEW_7.md | LINT sampling, the PIXBLT source-word check, I/O keep masks, two GSPs (d5ab06b..d67fc17) |

`<scratch>` in the reports stands for the reviewer's own working folder; the copies and logs kept there are not
part of the repository.

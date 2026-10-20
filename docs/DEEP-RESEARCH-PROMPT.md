# ChatGPT Deep Research prompt

Saved: 2026-10-18. Copy the text below into ChatGPT Deep Research.

Investigate published HCUP National Inpatient Sample (NIS) studies to identify evidence-based opportunities to improve easyNIS, an R package for NIS analysis.

Context and scope
- Package: https://github.com/MSaadAsif/easyNIS
- Documentation: https://msaadasif.github.io/easyNIS/
- The myectomy versus alcohol septal ablation study is already completed: https://msaadasif.github.io/NIS-Saad-HOCM-SRT-Pacing/
  Use it only as an existing reference if accessible. Do not propose recreating or extending it as a new study.
- The following extensions from docs/backlog/hocm-srt-pacing-gaps.md are deferred:
  - Curated cardiac device code sets, proposed as nis_codes_cardiac_device().
  - AHRQ Elixhauser comorbidity computation, proposed as nis_comorbidity_ahrq().
  Do not develop, schedule, or recommend starting these extensions. You may record related requirements from papers, but label those requirements as deferred rather than placing them in the actionable backlog. This does not exclude documenting or using existing nis_comorbidity() functionality.
- Independent statistical validation and complete teaching studies remain eligible improvement ideas. They are not deferred. Keep the completed HOCM research study separate from any future teaching-workflow proposal.
- This is literature and requirements research. Do not perform patient-level analysis or claim replication.

1. Establish the package baseline
Inspect the current public documentation and repository. Record the branch or commit and access date when possible. Read docs/IMPROVEMENT-ROADMAP.md if available.
Summarize existing capabilities and documented limitations. Distinguish released features, development features, historical backlog proposals, and unverified assumptions. If sources are inaccessible, state that and avoid declaring features absent.

2. Select a diverse study set
Find approximately 12 full-length original research articles, preferably published from 2016 onward, in JACC, JAMA, their specialty journals, Circulation, European Heart Journal, Annals of Internal Medicine, or comparable journals.
Prioritize methodological diversity and accessible full text and supplements over prestige. Clearly identify conference abstracts and exclude them from the main set.
Verify that NIS is an actual analytical dataset. Exclude studies using only NRD, SID, Medicare claims, or registries. Identify mixed-dataset studies and isolate their NIS-specific methods.
Cover national trends, comparative procedures, disparities, rare conditions or outcomes, resource utilization, procedure timing, and coding transitions. Avoid a set dominated by similar logistic-regression papers.

3. Extract reproducible requirements
For each paper, report:
- Citation, DOI, article link, supplement link, and source accessibility.
- NIS years, clinical question, unit of analysis, target population, and estimand.
- Sequential inclusion and exclusion criteria, including transfers and overlapping procedures where relevant.
- Diagnosis and procedure code definitions, systems, positions, validity periods, and code lists where available.
- Exposures, comparators, outcomes, covariates, comorbidity methods, and procedure-timing rules.
- Survey weights, strata, clusters, domain handling, pooled-year handling, and annualization.
- Missing-data methods, statistical models, propensity methods, balance diagnostics, interactions, adjusted estimates, and sensitivity analyses.
- Required tables, figures, denominators, uncertainty measures, and disclosure handling.
- Missing details that prevent faithful reconstruction.

Cite the section, table, supplement, or page supporting each substantive extraction. Mark details as "not reported" or "inaccessible" rather than guessing. Label your proposed reconstruction separately from the authors' reported methods.

4. Assess methodological suitability
Check reported approaches against official HCUP guidance and relevant primary methodological sources.
Consider hospitalization versus patient interpretation, unsupported longitudinal outcomes, geographic or hospital-volume claims, survey design, coding transitions, partial years, secondary diagnoses interpreted as complications, and costs versus charges.
Journal prestige is not methodological validation. Distinguish an inappropriate method from insufficient reporting and explain the evidence.

5. Map requirements to easyNIS
Build a cross-study matrix classifying each requirement as:
A. Supported directly by the current package.
B. Supported through ordinary survey, srvyr, or other established R tools.
C. Requires repetitive custom work that may justify an easyNIS improvement.
D. Unsupported, unclear, or methodologically inappropriate.

Cite package evidence for A. Describe the evidence needed to resolve uncertainty.
Separate software gaps, documentation gaps, data limitations, and scientific decisions. Do not propose a wrapper solely because a paper uses a statistical method.

6. Recommend the next improvements
Rank 5-8 candidate improvements using frequency across studies, consequence of error, reliable analyst effort saved, implementation complexity, and strength of evidence.
For each, give a concrete study example, existing support, remaining friction, proposed behavior, and a bounded next step. Treat these as proposals, not authorized implementation.
Include opportunities in cohort provenance, methodological preflight, reviewer-request sensitivity workflows, analyst usability, and annual schema compatibility when supported by findings.
Keep the completed HOCM study and the deferred extensions named above out of new-work recommendations. Put any evidence concerning those extensions in a separate deferred-requirements note.

Deliver:
- A concise synthesis.
- A cited study inventory and extraction table.
- A cross-study capability matrix.
- A prioritized improvement backlog.
- A separate deferred-requirements note, if the selected papers reveal needs related to the two deferred extensions.
- Unresolved questions and source-access limitations.

Use primary articles, supplements, official HCUP documentation, and official software documentation. Do not invent code lists, unavailable methods, package behavior, or numerical results.

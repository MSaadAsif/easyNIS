# NIS research

This glossary defines the research concepts used by easyNIS. Definitions follow the [HCUP documentation](https://hcup-us.ahrq.gov/nisoverview.jsp); proposed software interfaces are described separately.

## Language

**NIS**:
The HCUP National Inpatient Sample, called the Nationwide Inpatient Sample before the 2012 redesign. It is a sample used to estimate inpatient hospital utilization and outcomes.
_Avoid_: A complete census of US hospitalizations.

**Discharge**:
A hospital stay represented by a discharge record. One person can have multiple stays, and NIS does not provide longitudinal patient linkage.
_Avoid_: Unique patient, person, readmission episode.

**Data year**:
The calendar year of the hospital discharges in an annual NIS release. It differs from the year the files became available.
_Avoid_: Publication year, release date.

**Release revision**:
A particular corrected or distributed version of a data-year release. A data year alone may not identify all file corrections.

**Component**:
A discharge-level or hospital-level file belonging to a NIS release, such as Core, Hospital, Severity, or Diagnosis and Procedure Groups.

**Coding era**:
The applicable diagnosis and procedure coding system for a discharge, including the ICD-9-CM and ICD-10-CM/PCS portions of 2015.
_Avoid_: A single coding system for every discharge in 2015.

**Cohort**:
The hospital stays that satisfy a stated study eligibility definition.
_Avoid_: Linked patients.

**Analytic domain**:
A subpopulation for which a survey estimate is calculated while accounting for the original survey design.
_Avoid_: An independently sampled subgroup.

**Discharge weight**:
A weight used to estimate the number of hospital stays represented by a sampled discharge.

**Trend weight**:
An HCUP weight supplied for specified historical NIS years to improve comparability with the redesigned NIS. It is not a universal weight for all historical years.

**Estimand**:
The explicitly defined research quantity, such as an annual national total, an average annual total, or a proportion across several years.

**Charge**:
A hospital's billed amount for a stay. It differs from the resources used to provide care and from payment received.
_Avoid_: Cost, reimbursement.

**Cost estimate**:
An estimate of resources used for care, potentially derived from charges using an applicable cost-to-charge ratio. Its interpretation depends on the method and year.

**Synthetic record**:
An invented example hospital stay that contains no actual HCUP record or record-derived identifying information.
_Avoid_: De-identified HCUP sample.

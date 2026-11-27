import DuckDBProofs.RatSums

namespace DuckDBProofs.Taylor

abbrev Score := Rat × Rat

def xSum (xs : List Score) : Rat := (xs.map Prod.fst).sum
def ySum (xs : List Score) : Rat := (xs.map Prod.snd).sum
def raw (xs : List Score) : Rat := (xs.map fun p => p.1 * p.2).sum

-- R/lazy-survey-stat.R:nis_survey_aggregate and nis_survey_scores.
-- w and wy are PSU sums. W and WY sum over the domain, and W is nonzero.
theorem anchoredMeanScore (w wy a W WY : Rat) (h : W ≠ 0) :
    ((wy - a * w) - w * ((WY - a * W) / W)) / W =
      (wy - w * (WY / W)) / W := by
  have inverse : W * W⁻¹ = 1 := Rat.mul_inv_cancel W h
  simp only [Rat.div_def]
  grind

-- One PSU's SQL WHERE/FILTER, before finite complete records are reduced.
-- A survey-domain NULL is represented by false; missing values reaching
-- svyrecvar as non-finite scores are outside the exact-field theorem.
def inAggregate (removeNA inside complete : Bool) := inside && (!removeNA || complete)

structure Record where
  inside : Bool
  complete : Bool
  weight : Rat
  value : Rat

def rowLevel (r : Record) (removeNA : Bool) : Rat :=
  if r.inside then
    if removeNA && !r.complete then 0 else r.weight * r.value
  else 0

theorem domainSum (rs : List Record) (removeNA : Bool) :
    (((rs.filter fun r => inAggregate removeNA r.inside r.complete).map
      fun r => r.weight * r.value).sum) = (rs.map fun r => rowLevel r removeNA).sum := by
  induction rs with
  | nil => rfl
  | cons r rs ih =>
    rcases r with ⟨inside, complete, w, y⟩
    cases removeNA <;> cases inside <;> cases complete <;>
      simp [inAggregate, rowLevel, Rat.zero_add] at ih ⊢ <;> rw [ih]

def centered (xs : List Score) (a b : Rat) : Rat :=
  (xs.map fun p => (p.1 - a) * (p.2 - b)).sum

def moments (xs : List Score) (n : Nat) (a b : Rat) : Rat :=
  raw xs - b * xSum xs - a * ySum xs + (n : Rat) * a * b

theorem centerExpand (xs : List Score) (a b : Rat) :
    centered xs a b = moments xs xs.length a b := by
  induction xs with
  | nil => simp [centered, moments, raw, xSum, ySum] <;> grind
  | cons p ps ih =>
    change (p.1 - a) * (p.2 - b) + centered ps a b = _
    rw [ih]
    simp [moments, raw, xSum, ySum, Rat.natCast_add]
    grind

-- R/lazy-survey.R:nis_survey_variance passes PSU sums and roster n_h to
-- survey 4.5 onestrat, which pads sampled-but-inactive PSUs with zero.
def padded (xs : List Score) (missing : Nat) :=
  xs ++ List.replicate missing ((0, 0) : Score)

theorem paddedMoments (xs : List Score) (missing : Nat) (a b : Rat) :
    centered (padded xs missing) a b = moments xs (xs.length + missing) a b := by
  rw [centerExpand]
  simp [padded, moments, raw, xSum, ySum, sumAppend, Rat.add_zero]

@[simp] theorem paddedX (xs : List Score) (missing : Nat) :
    xSum (padded xs missing) = xSum xs := by
  simp [xSum, padded, sumAppend, Rat.add_zero]

@[simp] theorem paddedY (xs : List Score) (missing : Nat) :
    ySum (padded xs missing) = ySum xs := by
  simp [ySum, padded, sumAppend, Rat.add_zero]

def surveyGrand (strata : List (Nat × List Score)) : Score :=
  let active := strata.filter fun s => !s.2.isEmpty
  let n := (active.map Prod.fst).sum
  ((xSum (active.flatMap Prod.snd)) / (n : Rat), (ySum (active.flatMap Prod.snd)) / (n : Rat))

def grandFold (strata : List (Nat × List Score)) : Rat × Rat × Nat :=
  strata.foldr (fun (n, xs) (x, y, count) =>
    if xs.isEmpty then (x, y, count) else (xSum xs + x, ySum xs + y, n + count)) (0, 0, 0)

theorem grandFoldTotals (strata : List (Nat × List Score)) :
    let active := strata.filter fun s => !s.2.isEmpty
    grandFold strata =
      (xSum (active.flatMap Prod.snd), ySum (active.flatMap Prod.snd), (active.map Prod.fst).sum) := by
  induction strata with
  | nil => rfl
  | cons h hs ih =>
    rcases h with ⟨n, xs⟩
    cases xs <;> simp_all [grandFold, xSum, ySum, sumAppend, Rat.add_assoc]

def engineGrand (strata : List (Nat × List Score)) : Score :=
  let (x, y, n) := grandFold strata
  (x / (n : Rat), y / (n : Rat))

theorem grandCenter (strata : List (Nat × List Score)) :
    engineGrand strata = surveyGrand strata := by
  unfold engineGrand surveyGrand
  rw [grandFoldTotals]

-- onestage only visits strata represented by scores. Within a nonempty
-- stratum with one-stage sampling and FPC=1, onestrat selects the local
-- center unless adjustment is enabled for the corresponding singleton.
def localCenter (adjust domainAdjust : Bool) (m n : Nat) : Prop :=
  adjust = false ∨ m > 1 ∨ (n > 1 ∧ domainAdjust = false)

def grandCenterNeeded (adjust domainAdjust : Bool) (m n : Nat) : Prop :=
  adjust = true ∧ m = 1 ∧ (n = 1 ∨ domainAdjust = true)

theorem centerSelection (adjust domainAdjust : Bool) (m n : Nat) (hm : 0 < m) (hn : m ≤ n) :
    localCenter adjust domainAdjust m n ↔ ¬ grandCenterNeeded adjust domainAdjust m n := by
  cases adjust <;> cases domainAdjust <;>
    simp [localCenter, grandCenterNeeded] <;> omega

open Classical in
noncomputable def surveyStratum (xs : List Score) (missing : Nat)
    (adjust domainAdjust : Bool) (grand : Score) : Option Rat :=
  let n := xs.length + missing
  let all := padded xs missing
  if xs.isEmpty then some 0
  else if n = 1 ∧ adjust = false then none
  else
    let (a, b) := if localCenter adjust domainAdjust xs.length n
      then (xSum all / (n : Rat), ySum all / (n : Rat)) else grand
    let scale : Rat := if n = 1 then 1 else (n : Rat) / (n - 1 : Nat)
    some (scale * centered all a b)

open Classical in
noncomputable def engineStratum (xs : List Score) (missing : Nat)
    (adjust domainAdjust : Bool) (grand : Score) : Option Rat :=
  let n := xs.length + missing
  if xs.isEmpty then some 0
  else if n = 1 ∧ adjust = false then none
  else
    let (a, b) := if grandCenterNeeded adjust domainAdjust xs.length n
      then grand else (xSum xs / (n : Rat), ySum xs / (n : Rat))
    let scale : Rat := if n = 1 then 1 else (n : Rat) / (n - 1 : Nat)
    some (scale * moments xs n a b)

theorem stratumVariance (xs : List Score) (missing : Nat)
    (adjust domainAdjust : Bool) (grand : Score) :
    engineStratum xs missing adjust domainAdjust grand =
      surveyStratum xs missing adjust domainAdjust grand := by
  cases xs with
  | nil => simp [engineStratum, surveyStratum]
  | cons p ps =>
    let xs := p :: ps
    have h := centerSelection adjust domainAdjust xs.length (xs.length + missing)
      (by simp [xs]) (by omega)
    change engineStratum xs missing adjust domainAdjust grand =
      surveyStratum xs missing adjust domainAdjust grand
    by_cases g : grandCenterNeeded adjust domainAdjust xs.length (xs.length + missing)
    · have notLocal : ¬ localCenter adjust domainAdjust xs.length (xs.length + missing) :=
        fun useLocal => (h.mp useLocal) g
      simp [engineStratum, surveyStratum, g, notLocal, paddedMoments]
    · have useLocal := h.mpr g
      simp [engineStratum, surveyStratum, g, useLocal, paddedMoments]

structure Stratum where
  active : List Score
  missing : Nat

def roster (strata : List Stratum) : List (Nat × List Score) :=
  strata.map fun h => (h.active.length + h.missing, h.active)

def pooledCovariance : List (Option Rat) → Option Rat
  | [] => some 0
  | some x :: xs => (pooledCovariance xs).map (x + ·)
  | none :: _ => none

-- onestage combines one entry at a time in the covariance matrix. With
-- finite scores, contributions are present except for the explicit fail
-- policy. Empty domain strata are equivalent to adding zero.
theorem taylorVariance (strata : List Stratum) (adjust domainAdjust : Bool) :
    pooledCovariance (strata.map fun h => engineStratum h.active h.missing adjust
      domainAdjust (engineGrand (roster strata))) =
    pooledCovariance (strata.map fun h => surveyStratum h.active h.missing adjust
      domainAdjust (surveyGrand (roster strata))) := by
  simp [grandCenter, stratumVariance]

end DuckDBProofs.Taylor

import DuckDBProofs.RatSums

namespace DuckDBProofs.IRLS

-- R/lazy-survey-glm.R:nis_survey_model_system, nis_survey_cross_terms,
-- nis_survey_irls. Each group has common normalized x, y and fixed beta
-- after the row-level starting system, hence common eta, mu, d, and dev.
-- Each entry of X'WX and X'Wz and the deviance is a weighted common term.
structure Working where
  xj : Rat
  xk : Rat
  derivative : Rat
  eta : Rat
  response : Rat
  mean : Rat
  deviance : Rat

inductive Metric where
  | cross | right | deviance

def factor (p : Working) : Metric → Rat
  | .cross => p.derivative * p.xj * p.xk
  | .right => p.xj * (p.derivative * p.eta + (p.response - p.mean))
  | .deviance => p.deviance

abbrev Group := Working × List Rat

def grouped (metric : Metric) (gs : List Group) : Rat :=
  (gs.map fun (p, weights) => weights.sum * factor p metric).sum

def rowLevel (metric : Metric) (gs : List Group) : Rat :=
  ((gs.flatMap fun (p, weights) => weights.map fun w => w * factor p metric)).sum

theorem factorSum (weights : List Rat) (f : Rat) :
    weights.sum * f = (weights.map fun w => w * f).sum := by
  induction weights with
  | nil => simp
  | cons w ws ih => simp [Rat.add_mul, ih]

theorem groupedSystem (metric : Metric) (gs : List Group) :
    grouped metric gs = rowLevel metric gs := by
  induction gs with
  | nil => rfl
  | cons g gs ih =>
    rcases g with ⟨p, weights⟩
    simp [grouped, rowLevel, sumAppend, factorSum] at ih ⊢
    rw [ih]

end DuckDBProofs.IRLS

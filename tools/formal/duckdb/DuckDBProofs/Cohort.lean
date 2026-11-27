namespace DuckDBProofs.Cohort

structure Discharge where
  year : Nat
  hospital : Nat
  valid : Bool
  membership : Option Bool

def patient (row : Discharge) : Bool :=
  row.valid && row.membership.getD false

def represented (rows : List Discharge) (year hospital : Nat) : Bool :=
  rows.any fun row => patient row && row.year == year && row.hospital == hospital

theorem represented_iff (rows : List Discharge) (year hospital : Nat) :
    represented rows year hospital = true ↔
      ∃ row ∈ rows, row.valid = true ∧ row.membership = some true ∧
        row.year = year ∧ row.hospital = hospital := by
  have membership (value : Option Bool) : value.getD false = true ↔ value = some true := by
    cases value <;> simp
  simp [represented, List.any_eq_true, patient, membership, and_assoc]

-- The left side is evaluated only for keys in the distinct sampled roster.
theorem placeholder_iff (rows : List Discharge) (year hospital : Nat) :
    (!represented rows year hospital) = true ↔
      ¬ ∃ row ∈ rows, row.valid = true ∧ row.membership = some true ∧
        row.year = year ∧ row.hospital = hospital := by
  rw [← represented_iff]
  cases represented rows year hospital <;> decide

end DuckDBProofs.Cohort

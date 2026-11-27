import Lean

namespace DuckDBProofs

theorem sumAppend (xs ys : List Rat) : (xs ++ ys).sum = xs.sum + ys.sum := by
  induction xs with
  | nil => simp [Rat.zero_add]
  | cons x xs ih => simp [ih, Rat.add_assoc]

@[simp] theorem sumZeros (n : Nat) : (List.replicate n (0 : Rat)).sum = 0 := by
  induction n with
  | zero => rfl
  | succ n ih => simp [List.replicate_succ, ih, Rat.zero_add]

end DuckDBProofs

import Lean

namespace DuckDBProofs.Slots

-- R/code-flags.R:nis_code_match, R/pr-timing.R:timing_index_day,
-- R/procedure-days.R:nis_decode_procedure_day, and
-- R/comorbidity-sql.R:nis_cmrb_inputs/nis_cmrb_score_sql.
-- One item is the paired code/day/POA from a single slot. UNPIVOT must
-- preserve those associations. Decode non-usable days to none first.
structure Slot where
  matched : Bool
  era : Bool
  day : Option Rat
  principal : Bool
  positive : Bool
  exempt : Bool
  unrestricted : Bool

def code (x : Slot) : Bool := x.era && x.matched
def eligiblePoa (x : Slot) : Bool := x.positive || x.exempt || x.unrestricted

def prefer : Option Rat → Option Rat → Option Rat
  | none, b => b
  | a, none => a
  | some a, some b => some (min a b)

def wideDay : List Slot → Option Rat
  | [] => none
  | x :: xs => prefer (if code x then x.day else none) (wideDay xs)

def longRows (xs : List Slot) := xs.filter code

def longDay (xs : List Slot) :=
  ((longRows xs).filterMap Slot.day).foldr (fun d a => prefer (some d) a) none

theorem anyMatch (xs : List Slot) :
    !(longRows xs).isEmpty = xs.any code := by
  induction xs with
  | nil => rfl
  | cons x xs ih =>
    cases h : code x <;> simp_all [longRows]

theorem earliest (xs : List Slot) : longDay xs = wideDay xs := by
  induction xs with
  | nil => rfl
  | cons x xs ih =>
    cases h : code x <;> cases d : x.day <;>
      simp_all [longDay, longRows, wideDay, prefer]

-- SQL can return the long rows in any order. The minimum fold is invariant
-- under a permutation of the eligible slots.
theorem earliestAfterUnpivot (wide rows : List Slot) (perm : rows.Perm (longRows wide)) :
    (rows.filterMap Slot.day).foldr (fun d a => prefer (some d) a) none = wideDay wide := by
  calc
    _ = longDay wide := by
      apply (perm.filterMap Slot.day).foldr_eq'
      intro x _ y _ acc
      cases acc <;> simp only [prefer, Option.some.injEq] <;> grind
    _ = wideDay wide := earliest wide

def widePoa (xs : List Slot) :=
  xs.any fun x => code x && !x.principal && eligiblePoa x

def longPoa (xs : List Slot) :=
  ((longRows xs).filter fun x => !x.principal).any eligiblePoa

theorem poaEvidence (xs : List Slot) : longPoa xs = widePoa xs := by
  induction xs with
  | nil => rfl
  | cons x xs ih =>
    cases h : code x <;> cases p : x.principal <;>
      simp_all [longPoa, longRows, widePoa]

-- Fix the release and category before comparing the slot-wise joins
-- with list membership. Missing slots cannot match a mapping code.
def ccsrCodes (mapping : List (String × String)) (category : String) : List String :=
  (mapping.filter (fun pair => pair.2 == category)).map Prod.fst

def ccsrPresence (codes : List String) (slots : List (Option String)) : Bool :=
  slots.any fun slot => slot.any fun code => codes.contains code

theorem ccsrLookup (mapping : List (String × String)) (category : String)
    (slots : List (Option String)) :
    ccsrPresence (ccsrCodes mapping category) slots = true ↔
      ∃ code, some code ∈ slots ∧ (code, category) ∈ mapping := by
  simp only [ccsrPresence, ccsrCodes, List.any_eq_true]
  constructor
  · rintro ⟨slot, inSlots, hit⟩
    cases slot with
    | none => simp at hit
    | some code =>
      simp only [Option.any, List.contains_iff_mem, List.mem_map, List.mem_filter,
        beq_iff_eq] at hit
      obtain ⟨⟨c, cat⟩, ⟨inMap, rfl⟩, rfl⟩ := hit
      exact ⟨_, inSlots, inMap⟩
  · rintro ⟨code, inSlots, inMap⟩
    refine ⟨some code, inSlots, ?_⟩
    simp only [Option.any, List.contains_iff_mem, List.mem_map, List.mem_filter, beq_iff_eq]
    exact ⟨(code, category), ⟨inMap, rfl⟩, rfl⟩

theorem ccsrSlotOrder (left right : List (Option String)) (order : left.Perm right)
    (codes : List String) :
    ccsrPresence codes left = ccsrPresence codes right := by
  rw [Bool.eq_iff_iff]
  simp only [ccsrPresence, List.any_eq_true, order.mem_iff]

end DuckDBProofs.Slots

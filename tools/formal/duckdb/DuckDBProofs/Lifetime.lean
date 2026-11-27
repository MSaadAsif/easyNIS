import Lean

namespace DuckDBProofs.Lifetime

inductive Reachable {S : Type} (step : S → S → Prop) (initial : S) : S → Prop
  | start : Reachable step initial initial
  | next : Reachable step initial s → step s t → Reachable step initial t

theorem invariant {S : Type} {step : S → S → Prop} {initial : S} {P : S → Prop}
    (base : P initial) (preserve : ∀ {s t}, step s t → P s → P t)
    {s : S} (trace : Reachable step initial s) : P s := by
  induction trace with
  | start => exact base
  | next _ action ih => exact preserve action ih

namespace Query

-- R/open.R:nis_open and R/duckdb.R:nis_duckdb_attach_finalizer hand
-- ownership to src. Deriving a query retains src (nis_add_ccsr,
-- nis_comorbidity_lazy). compute.tbl_nis must restore it on return (#198).
-- Counts model arbitrary live ordinary handles and references to one
-- connection-private materialization. Native operations are synchronous.
structure State where
  ordinary : Nat
  computed : Nat
  roots : Nat
  openDb : Bool
  table : Bool
  spill : Bool

def initial : State := ⟨1, 0, 0, true, false, true⟩
def keepComputeRoot : Bool := true
def keepLiveTable : Bool := true

inductive Step (retain : Bool) : State → State → Prop
  | derive (s : State) : 0 < s.ordinary →
      Step retain s {s with ordinary := s.ordinary + 1}
  | compute (s : State) : 0 < s.ordinary →
      Step retain s {s with
        computed := s.computed + 1
        roots := s.roots + (if retain then 1 else 0)
        table := true}
  | dropOrdinary (s : State) : 0 < s.ordinary →
      Step retain s {s with ordinary := s.ordinary - 1}
  | dropComputed (s : State) : 0 < s.computed →
      Step retain s {s with
        computed := s.computed - 1
        roots := s.roots - (if retain then 1 else 0)}
  -- nis_duckdb_open_data release closure disconnects before removing spill.
  | disconnect (s : State) : s.ordinary = 0 → s.roots = 0 →
      Step retain s {s with openDb := false, table := false}
  | dropTable (s : State) : (keepLiveTable = true → s.computed = 0) →
      Step retain s {s with table := false}
  | unlinkSpill (s : State) : s.openDb = false →
      Step retain s {s with spill := false}

def Safe (s : State) : Prop :=
  s.roots = s.computed ∧
    (0 < s.ordinary + s.computed → s.openDb = true) ∧
    (0 < s.computed → s.table = true)

theorem ownership (s : State) (trace : Reachable (Step keepComputeRoot) initial s) : Safe s := by
  apply invariant (P := Safe) (by simp [initial, Safe]) _ trace
  intro a b transition safe
  cases transition <;> simp_all [Safe, keepComputeRoot, keepLiveTable] <;> grind

-- R/collect-prudence.R:db_collect.nis_duckdb_connection and
-- R/duckdb.R:dbSendQuery. The caller can attempt collection from any live
-- handle. The predicate tests the real resource preconditions.
def canCollect (s : State) (computed : Bool) : Bool :=
  s.openDb && (!computed || s.table)

theorem liveQuerySafe {s : State} (trace : Reachable (Step keepComputeRoot) initial s)
    (computed : Bool) (live : 0 < if computed then s.computed else s.ordinary) :
    canCollect s computed = true := by
  obtain ⟨_, db, table⟩ := ownership s trace
  cases computed <;> simp_all [canCollect]
  all_goals exact db (by omega)

-- Explicit #198 counterexample: compute, discard the original query,
-- finalize the now-unrooted src, and collect the surviving query.
theorem lostComputeOwner :
    ∃ s, Reachable (Step false) initial s ∧ s.computed = 1 ∧ canCollect s true = false := by
  refine ⟨⟨0, 1, 0, false, false, true⟩, ?_, rfl, rfl⟩
  exact .next (.next (.next .start (.compute initial (by decide)))
    (.dropOrdinary ⟨1, 1, 0, true, true, true⟩ (by decide)))
    (.disconnect ⟨0, 1, 0, true, true, true⟩ rfl rfl)

theorem lastOwnerCanFinalize (s : State) (ordinary : s.ordinary = 0) (roots : s.roots = 0) :
    ∃ a b, Step keepComputeRoot s a ∧ Step keepComputeRoot a b ∧
      b.openDb = false ∧ b.table = false ∧ b.spill = false := by
  exact ⟨{s with openDb := false, table := false},
    {s with openDb := false, table := false, spill := false},
    .disconnect s ordinary roots, .unlinkSpill _ rfl, rfl, rfl, rfl⟩

end Query

namespace Scoped

-- R/lazy-survey-glm.R:nis_survey_irls (temporary table),
-- R/convert.R:nis_convert_copy_batch (registration),
-- R/comorbidity.R:nis_comorbidity_frame, R/ccsr-query.R:ccsr_bundled_codes
-- (private connection), R/duckdb.R:nis_duckdb_open_data (spill).
-- The handler is armed before acquisition. Connection assignments defer
-- interrupts until the handler can see the acquired connection.
inductive Phase where
  | start | armed | acquired | used
  | unwinding (resource handler : Bool)
  | returned (resource : Bool)
  deriving DecidableEq

def registerHandler : Bool := true

inductive Step : Phase → Phase → Prop
  | arm : Step .start .armed
  | acquire : Step .armed .acquired
  | run : Step .acquired .used
  | earlyError : Step .start (.unwinding false false)
  | openError : Step .armed (.unwinding false registerHandler)
  | acquiredError : Step .acquired (.unwinding true registerHandler)
  | successOrError : Step .used (.unwinding true registerHandler)
  | exit (present handler : Bool) :
      Step (.unwinding present handler) (.returned (present && !handler))

def Safe : Phase → Prop
  | .unwinding present handler => present = true → handler = true
  | .returned present => present = false
  | _ => True

theorem registeredCleanup {s : Phase} (trace : Reachable Step .start s) : Safe s := by
  apply invariant (P := Safe) (by simp [Safe]) _ trace
  intro a b transition safe
  cases transition <;> simp_all [Safe, registerHandler]

end Scoped

namespace Writer

-- R/convert.R:nis_convert_with_stage,
-- nis_convert_copy_batch, nis_convert_check_count, nis_convert_publish.
-- R/write-cohort.R:nis_write_cohort, nis_cohort_copy_parquet,
-- nis_cohort_check_count. R/duckdb.R:nis_remove_owned_directory.
-- One writer, an initially absent or previously existing target, a
-- synchronous COPY, successful close/unlink, and same-parent atomic rename.
inductive Target where
  | absent | previous | published (parts : Nat)
  deriving DecidableEq

inductive Phase where
  | start | checked | staged
  | writing (parts : Nat) | named (parts : Nat) | reading (parts : Nat)
  | readCount (parts : Nat) | validated (parts : Nat) | closed (parts : Nat)
  | done (stage db : Bool)
  deriving DecidableEq

structure State where
  phase : Phase
  target : Target
  renamedWithHandle : Bool

def initial (target : Target) : State := ⟨.start, target, false⟩
def verifyAllParts : Bool := true
def closeBeforePublish : Bool := true

-- Both outer stage cleanup and inner DB cleanup are scoped on.exit
-- handlers. A borrowed source DB is not counted as a private stage handle.
structure Cleanup where
  stage : Bool
  stageHandler : Bool
  db : Bool
  dbHandler : Bool
  readHandle : Bool

def registerStageHandler : Bool := true
def registerDbHandler : Bool := true
def closeBeforeUnlink : Bool := true

def resources (cohort : Bool) : Phase → Cleanup
  | .start | .checked => ⟨false, false, false, false, false⟩
  | .writing _ => ⟨true, registerStageHandler, !cohort, !cohort && registerDbHandler, false⟩
  | .reading _ => ⟨true, registerStageHandler, true, registerDbHandler, false⟩
  | .readCount _ | .validated _ => ⟨true, registerStageHandler, true, registerDbHandler, true⟩
  | .staged | .named _ | .closed _ => ⟨true, registerStageHandler, false, false, false⟩
  | .done stage db => ⟨stage, false, db, false, false⟩

def releaseDb (r : Cleanup) : Cleanup :=
  if r.dbHandler then {r with db := false, readHandle := false} else r

def unlinkStage (r : Cleanup) : Cleanup :=
  if r.stageHandler && !r.readHandle then {r with stage := false} else r

def unwind (cohort : Bool) (phase : Phase) : Phase :=
  let r := resources cohort phase
  let cleaned := if closeBeforeUnlink then unlinkStage (releaseDb r) else releaseDb (unlinkStage r)
  .done cleaned.stage cleaned.db

def hasReadHandle : Phase → Bool
  | .readCount _ | .validated _ => true
  | _ => false

inductive Advance (cohort : Bool) (expected : Nat) : Phase → Phase → Prop
  | check : Advance cohort expected .start .checked
  -- Cleanup is armed before each acquisition. An interrupted connection
  -- acquisition can unwind once the assignment completes.
  | mkdir : Advance cohort expected .checked .staged
  | openConvert : cohort = false → Advance cohort expected .staged (.writing 0)
  | borrow : cohort = true → Advance cohort expected .staged (.writing 0)
  | copy (n : Nat) : n < expected → Advance cohort expected (.writing n) (.writing (n + 1))
  | nameCohort (n : Nat) : cohort = true → Advance cohort expected (.writing n) (.named n)
  | openValidation (n : Nat) : Advance cohort expected (.named n) (.reading n)
  | readConversion (n : Nat) : cohort = false → Advance cohort expected (.writing n) (.readCount n)
  | readValidation (n : Nat) : Advance cohort expected (.reading n) (.readCount n)
  | validate (n : Nat) : (verifyAllParts = true → n = expected) →
      Advance cohort expected (.readCount n) (.validated n)
  | close (n : Nat) : Advance cohort expected (.validated n) (.closed n)

inductive Step (cohort : Bool) (expected : Nat) : State → State → Prop
  | advance (s : State) (to : Phase) : s.target = .absent → Advance cohort expected s.phase to →
      Step cohort expected s {s with phase := to}
  | unwind (s : State) :
      Step cohort expected s {s with phase := Writer.unwind cohort s.phase}
  | publish (s : State) (n : Nat) : s.target = .absent →
      s.phase = (if closeBeforePublish then .closed n else .validated n) →
      Step cohort expected s
        ⟨.done false false, .published n, hasReadHandle s.phase⟩

def Whole (expected : Nat) (s : State) : Prop :=
  (∀ n, s.target = .published n → n = expected) ∧ s.renamedWithHandle = false

def CompleteIfReady (expected : Nat) : Phase → Prop
  | .validated n | .closed n => n = expected
  | _ => True

theorem advanceComplete {p q : Phase} (advance : Advance cohort expected p q)
    (ready : CompleteIfReady expected p) : CompleteIfReady expected q := by
  cases advance <;> simp_all [CompleteIfReady, verifyAllParts]

theorem publicationSafe {s : State} (cohort : Bool) (expected : Nat)
    (target : Target) (absentOrPrevious : target = .absent ∨ target = .previous)
    (trace : Reachable (Step cohort expected) (initial target) s) :
    Whole expected s := by
  have both := invariant
    (P := fun s => Whole expected s ∧ CompleteIfReady expected s.phase)
    (by rcases absentOrPrevious with rfl | rfl <;> simp [initial, Whole, CompleteIfReady])
    (by
      intro a b action safe
      rcases safe with ⟨whole, ready⟩
      cases action with
      | advance to absent advance =>
        exact ⟨whole, advanceComplete advance ready⟩
      | unwind =>
        exact ⟨whole, by simp [CompleteIfReady, Writer.unwind]⟩
      | publish n absent closed =>
        simp [closeBeforePublish] at closed
        simp_all [Whole, CompleteIfReady, hasReadHandle]) trace
  exact both.1

theorem previousTargetPreserved {s : State} (cohort : Bool) (expected : Nat)
    (trace : Reachable (Step cohort expected) (initial .previous) s) :
    s.target = .previous := by
  apply invariant (P := fun a => a.target = .previous) rfl _ trace
  intro a b action old
  cases action <;> simp_all

def ExitClean : Phase → Prop
  | .done stage db => stage = false ∧ db = false
  | _ => True

theorem advanceClean {p q : Phase} (advance : Advance cohort expected p q) : ExitClean q := by
  cases advance <;> trivial

theorem registeredWriterCleanup {s : State} (cohort : Bool) (expected : Nat) (target : Target)
    (trace : Reachable (Step cohort expected) (initial target) s) : ExitClean s.phase := by
  apply invariant (P := fun s => ExitClean s.phase) (by simp [initial, ExitClean]) _ trace
  intro a b action safe
  cases action with
  | advance to _ advance => exact advanceClean advance
  | unwind =>
    cases cohort <;> cases h : a.phase <;> simp_all [Writer.unwind, resources, releaseDb, unlinkStage,
      closeBeforeUnlink, registerStageHandler, registerDbHandler, ExitClean]
  | publish => simp [ExitClean]

end Writer

end DuckDBProofs.Lifetime

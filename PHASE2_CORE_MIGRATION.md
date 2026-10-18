# Migrating OlympusMons to F* phase-2 Core (FStarLang/FStar#4605)

This report covers the upgrade of every OlympusMons project from F* `master`
(`285d2038e2`) to the phase-2 Core PR, FStarLang/FStar#4605 (branch
`_phase2_core`, PR head at the start: `8615b44ee6`). It records:

* the fixes made to the PR itself;
* each downstream change, with links to the exact lines;
* the **proof and spec bugs this exposed** (§3). This is the most useful
  part for judging the PR.

(hacl-pulse and OlympusMons are private repositories; their links need access.)

Short version:

* 7 commits were pushed to the PR branch: 4 fixes, 2 Custard fixes and 1 Pulse
  library change.
* 1 project change fixes a **genuine spec bug**: an ill-formed Pulse
  postcondition in hacl-pulse that the old Core accepted.
* 35 project changes are proof-robustness workarounds: asserts, helper lemmas,
  and local fuel/rlimit/option changes.
* pal needed no change.
* The full clean build of all 8 targets passes.

---

## 1. Result

### 1.1 Pins (`hashes.txt`, OlympusMons commit [`2b8d8c1`](https://github.com/FStarLang/OlympusMons/commit/2b8d8c1e3b4f96b0d55c979638e468783ad2fabe), branch `olympus_phase2_core`)

| Project | Before (`main`) | After (`olympus_phase2_core`) | Commits |
|---|---|---|---|
| FStar | `285d2038e2` (master) | [`b7cd6d4daa`](https://github.com/FStarLang/FStar/commit/b7cd6d4daa19eae8b34f754e961f47abc675db62) (`_phase2_core`) | PR head `8615b44ee6` + 7 |
| everparse | `56efa51529` | [`071a7d4551`](https://github.com/project-everest/everparse/commit/071a7d4551c299d1a8de2b51452d67fd0722aaca) | 1 |
| pal | `51b8c40fe3` | `51b8c40fe3` (unchanged) | 0 |
| kuiper | `b5477e22c7` | [`8487b55cfe`](https://github.com/FStarLang/kuiper/commit/8487b55cfeba4d34ff7e9fa117be58266353e239) | 6 |
| pulse-verified-gc | `ff83de91ce` | [`589bf2e88e`](https://github.com/FStarLang/pulse-verified-gc/commit/589bf2e88ed03bc489c0b638303d90730fdcb4a7) | 4 |
| AlgoStar | `1434213760` | [`018870fa82`](https://github.com/FStarLang/AlgoStar/commit/018870fa826ccda4ef945eb6763e789c8684a9d5) | 12 |
| hacl-pulse | `bc7c41e429` | [`49c09320c3`](https://github.com/FStarLang/hacl-pulse/commit/49c09320c36cc80638220ee611debf481312df5c) | 13 |

Each project's `olympus_phase2_core` branch is its previously pinned commit
plus the commits listed in §4. Each commit carries an `Olympus-Change:` trailer:

* `minimal`: a genuine fix;
* `fstar-regression-workaround`: a proof made robust to the new checker.

### 1.2 Final clean build (`make -k -j128 CLEAN=1`)

| Target | Time | Result |
|---|---|---|
| FStar | 10m51s | ✅ |
| FStar-ci | 52m | ✅ |
| everparse | 1h35m | ✅ |
| pal | 25m | ✅ |
| kuiper | 1h07m | ✅ |
| pulse-verified-gc | 52m | ✅ |
| AlgoStar | 17m | ✅ |
| hacl-pulse | 1h10m | ✅ |

---

## 2. Changes to the PR (FStarLang/FStar `_phase2_core`, `8615b44ee6..b7cd6d4daa`)

### 2.1 [`aa36780690`](https://github.com/FStarLang/FStar/commit/aa36780690f475789bde0324852891bceff2c833) Core: check an unannotated match argument against the formal's type

* **Code:** [Core.fst L2701–L2718](https://github.com/FStarLang/FStar/blob/aa36780690f475789bde0324852891bceff2c833/src/typechecker/FStarC.TypeChecker.Core.fst#L2701-L2718)
  (`check_app_arg`: `unannotated_match` joins the `abs_checked` path).
* **Test:** [pulse/test/bug-reports/IfJoinRefinedBranch.fst](https://github.com/FStarLang/FStar/blob/aa36780690f475789bde0324852891bceff2c833/pulse/test/bug-reports/IfJoinRefinedBranch.fst#L1-L22)
* **Symptom:** Pulse functions whose `if` joins the values of a `let mut` from
  differently-typed branches were rejected, e.g. `Expected {v _ == 0} got SizeT.t`:
  * pal `Func_lookup`, `Func_next_color`, `Func_explicit_fallthrough`;
  * AlgoStar Queue, NaiveStringMatch;
  * hacl-pulse MLKEM.NTT:247;
  * kuiper RowReduce, HReduce.Max (`Expected perm got real`).
* **Cause:** Pulse's join builds `pts_to r (match b with true -> 0ul | false -> g c)`
  with no return annotation. Core *synthesized* the type of that match from its
  first branch (`x:U32.t{x == 0ul}`), which the other branch does not have.
  The fix checks such a match against the formal's type, the same way lambda
  arguments are already checked.
* Also see §3.2: the *old* Core was unsound here.

### 2.2 [`8ae419fd7d`](https://github.com/FStarLang/FStar/commit/8ae419fd7da0c32490da37cdc7eea3adbb7f7472) Phase 2 Core: check declared types in a separate query

* **Code:**
  * `check_declared_types`: [Tc.fst L460–L475](https://github.com/FStarLang/FStar/blob/8ae419fd7da0c32490da37cdc7eea3adbb7f7472/src/typechecker/FStarC.TypeChecker.Tc.fst#L460-L475)
  * its use for a single definition: [L494–L510](https://github.com/FStarLang/FStar/blob/8ae419fd7da0c32490da37cdc7eea3adbb7f7472/src/typechecker/FStarC.TypeChecker.Tc.fst#L494-L510)
  * its use for a let-rec nest: [L553](https://github.com/FStarLang/FStar/blob/8ae419fd7da0c32490da37cdc7eea3adbb7f7472/src/typechecker/FStarC.TypeChecker.Tc.fst#L553)
  * the new `p1typ_annotated` flag: [L403–L407](https://github.com/FStarLang/FStar/blob/8ae419fd7da0c32490da37cdc7eea3adbb7f7472/src/typechecker/FStarC.TypeChecker.Tc.fst#L403-L407), [L701–L714](https://github.com/FStarLang/FStar/blob/8ae419fd7da0c32490da37cdc7eea3adbb7f7472/src/typechecker/FStarC.TypeChecker.Tc.fst#L701-L714)
  * docs: [phase2_core.md L79–L95](https://github.com/FStarLang/FStar/blob/8ae419fd7da0c32490da37cdc7eea3adbb7f7472/doc/ref/phase2_core.md#L79-L95)
* **Symptom:** many SMT timeouts across AlgoStar, hacl-pulse and kuiper. With
  `--ext phase2_core=off` they passed.
* **Cause:** the well-formedness (WF) guard of a declared type (annotation,
  `val`, let-rec types) was *conjoined* with the body's guard. So the spec WF
  formula, which is a large quantified conjunct, became a hypothesis of every
  body goal. TcTerm discharges it first, in its own query. The fix does the same.
* This removed most regressions. For example, these went from failing to passing:
  * AlgoStar SortSpec, GrahamScan, Huffman.Impl, Strassen:363;
  * hacl UInt128.

### 2.3 [`486f8561c7`](https://github.com/FStarLang/FStar/commit/486f8561c7c3a9d2c4e86a3cc11f3c5790f08428) Phase 2 Core: bind the names of a let rec nest before the function's binders

A **latent bug in the PR**, detailed in §3.3.

* **Code:** [Tc.fst L556–L578](https://github.com/FStarLang/FStar/blob/486f8561c7c3a9d2c4e86a3cc11f3c5790f08428/src/typechecker/FStarC.TypeChecker.Tc.fst#L556-L578)
* **Docs:** [phase2_core.md L662–L669](https://github.com/FStarLang/FStar/blob/486f8561c7c3a9d2c4e86a3cc11f3c5790f08428/doc/ref/phase2_core.md#L662-L669)
* **Test:** [tests/bug-reports/closed/LetRecRefinedResultCall.fst](https://github.com/FStarLang/FStar/blob/486f8561c7c3a9d2c4e86a3cc11f3c5790f08428/tests/bug-reports/closed/LetRecRefinedResultCall.fst#L1-L13)
* **Expected-output change:** a failed termination goal now shows the function's
  binders in its context, as it does for a non-recursive function:
  [NegativeTests.Termination.fst.output.expected](https://github.com/FStarLang/FStar/blob/486f8561c7c3a9d2c4e86a3cc11f3c5790f08428/tests/error-messages/NegativeTests.Termination.fst.output.expected#L6-L8)
  (and 10 more hunks of the same kind).

### 2.4 [`297bdda360`](https://github.com/FStarLang/FStar/commit/297bdda3609d2beededfbaa8774f70d5df8fb168) Pulse.Lib.PriorityQueue: state the length of `swap_seq` in its type

* **Code:** [Pulse.Lib.PriorityQueue.fst L259–L260](https://github.com/FStarLang/FStar/blob/297bdda3609d2beededfbaa8774f70d5df8fb168/pulse/lib/pulse/lib/Pulse.Lib.PriorityQueue.fst#L259-L260)
* The WF of `grandparent_up_after_swap`'s postcondition needs
  `length (swap_seq s child p)`. Unfolding `swap_seq` to get it timed out,
  depending on the solver's history. This is a robustness change in a library
  that ships with F*.

### 2.5 [`88b08fcbae`](https://github.com/FStarLang/FStar/commit/88b08fcbae4f6592de149ed91d7c096d6260b14d) Custard: decide "exactly unit" binders up to ascription and beta/iota

* **Code:**
  * `is_unit_sort`: [Mono.fst L279–L312](https://github.com/FStarLang/FStar/blob/88b08fcbae4f6592de149ed91d7c096d6260b14d/src/custard/FStarC.Custard.Mono.fst#L279-L303)
  * uses: [L391](https://github.com/FStarLang/FStar/blob/88b08fcbae4f6592de149ed91d7c096d6260b14d/src/custard/FStarC.Custard.Mono.fst#L391), [L670](https://github.com/FStarLang/FStar/blob/88b08fcbae4f6592de149ed91d7c096d6260b14d/src/custard/FStarC.Custard.Mono.fst#L670), [L828](https://github.com/FStarLang/FStar/blob/88b08fcbae4f6592de149ed91d7c096d6260b14d/src/custard/FStarC.Custard.Mono.fst#L828)
* **Test:** [tests/custard/pulse/UnitErrArg.fst](https://github.com/FStarLang/FStar/blob/88b08fcbae4f6592de149ed91d7c096d6260b14d/tests/custard/pulse/UnitErrArg.fst#L1-L32)
* EverParse's `err:(if use_error_handler then error_handler else unit)` at
  `false` was treated inconsistently:
  * the arrow type kept it as a unit parameter;
  * call sites deleted the argument.
* KaRaMeL then rejected `SpecializeABC` under `--use_error_handler_macro`.
  Details in §3.4.

### 2.6 [`9a5fa7ed4b`](https://github.com/FStarLang/FStar/commit/9a5fa7ed4b8823feedfce2605ed4290b200e7002) Core: remember guard-free relation failures within a top-level check

* **Code:**
  * `with_relation_failure_memo`: [Core.fst L1374–L1431](https://github.com/FStarLang/FStar/blob/9a5fa7ed4b8823feedfce2605ed4290b200e7002/src/typechecker/FStarC.TypeChecker.Core.fst#L1374-L1431)
  * uses: [L2205](https://github.com/FStarLang/FStar/blob/9a5fa7ed4b8823feedfce2605ed4290b200e7002/src/typechecker/FStarC.TypeChecker.Core.fst#L2205), [L2217](https://github.com/FStarLang/FStar/blob/9a5fa7ed4b8823feedfce2605ed4290b200e7002/src/typechecker/FStarC.TypeChecker.Core.fst#L2217)
  * reset per top-level check: [L4358](https://github.com/FStarLang/FStar/blob/9a5fa7ed4b8823feedfce2605ed4290b200e7002/src/typechecker/FStarC.TypeChecker.Core.fst#L4358), [L4502](https://github.com/FStarLang/FStar/blob/9a5fa7ed4b8823feedfce2605ed4290b200e7002/src/typechecker/FStarC.TypeChecker.Core.fst#L4502), [L4516](https://github.com/FStarLang/FStar/blob/9a5fa7ed4b8823feedfce2605ed4290b200e7002/src/typechecker/FStarC.TypeChecker.Core.fst#L4516)
* **Test:** [tests/micro-benchmarks/CoreFailedChain.fst](https://github.com/FStarLang/FStar/blob/9a5fa7ed4b8823feedfce2605ed4290b200e7002/tests/micro-benchmarks/CoreFailedChain.fst#L1-L41)
* **Symptom:** an exponential hang. Details in §3.5.

### 2.7 [`b7cd6d4daa`](https://github.com/FStarLang/FStar/commit/b7cd6d4daa19eae8b34f754e961f47abc675db62) Custard: keep unit binders of definitions on the karamel backends

* **Code:**
  * `krml_keeps_unit_params`: [Mono.fst L314–L333](https://github.com/FStarLang/FStar/blob/b7cd6d4daa19eae8b34f754e961f47abc675db62/src/custard/FStarC.Custard.Mono.fst#L314-L333)
  * rule 1: [L848–L849](https://github.com/FStarLang/FStar/blob/b7cd6d4daa19eae8b34f754e961f47abc675db62/src/custard/FStarC.Custard.Mono.fst#L848-L849)
  * `eta_reduce`: [Simplify.fst L1094–L1100](https://github.com/FStarLang/FStar/blob/b7cd6d4daa19eae8b34f754e961f47abc675db62/src/custard/FStarC.Custard.Simplify.fst#L1094-L1100), [L1113–L1114](https://github.com/FStarLang/FStar/blob/b7cd6d4daa19eae8b34f754e961f47abc675db62/src/custard/FStarC.Custard.Simplify.fst#L1113-L1114)
* **Test:** [tests/custard/pulse/UnitFnValue.fst](https://github.com/FStarLang/FStar/blob/b7cd6d4daa19eae8b34f754e961f47abc675db62/tests/custard/pulse/UnitFnValue.fst#L1-L33)
* **The fix:** a definition's unit binders were deleted, but arrow types and
  calls through function values kept theirs. So a top-level `f (_:unit)`
  passed as a function value had the wrong type (KaRaMeL Warning 4). On
  KrmlC/KrmlRust these binders are now kept; KaRaMeL removes unit parameters
  uniformly itself.
* **`eta_reduce` adjustment:** it now stops while a *non-unit* binder remains.
  This keeps EverParse's CBOR C and Rust snapshots byte-identical; otherwise
  forwarding functions got their parameters renamed.

---

## 3. Exposed proof and checker bugs

### 3.1 hacl-pulse `Hacl.Impl.Sub.unsub`: an ill-formed postcondition (a genuine spec bug)

Commit: [hacl-pulse `5c171b3`](https://github.com/FStarLang/hacl-pulse/commit/5c171b319ea3138acdd5efa335d98a6ef63e5d9c) (`Olympus-Change: minimal`).
Fixed line: [lib/Hacl.Impl.Sub.fst L109](https://github.com/FStarLang/hacl-pulse/blob/5c171b319ea3138acdd5efa335d98a6ef63e5d9c/lib/Hacl.Impl.Sub.fst#L101-L113).

```fstar
ghost fn unsub (#t: Type0) (a: A.array t) (#p: perm)
               (i: nat) (j: nat { i <= j /\ j <= A.length a })
               (b: A.array t { b == A.gsub a i j })
               (#v: erased (Seq.seq t)) (#v': erased (Seq.seq t))
requires rest a p i j v ** A.pts_to b #p v' **
         pure (Seq.length v == A.length a /\ Seq.length v' == j - i)
ensures exists* (w: Seq.seq t).
  A.pts_to a #p w **
-  pure (Seq.length w == Seq.length v /\
+  pure (Seq.length w == Seq.length v /\ Seq.length v' == j - i /\
        (forall (k: nat). k < Seq.length w ==>
           Seq.index w k == (if i <= k && k < j
                             then Seq.index v' (k - i)    // needs k - i < length v'
                             else Seq.index v k)))
```

* **Why it is ill-formed:** `Seq.index v' (k - i)` needs
  `k - i < Seq.length v'`. In the postcondition nothing implies it.
  `Seq.length v' == j - i` was only in the *precondition*, and a postcondition
  must be well-formed on its own. Clients that assume `unsub`'s post rely on a
  formula whose well-typedness was never established.
* **Why it used to pass:**
  * The WF of a Pulse `ensures` is checked by Core, called from the Pulse
    checker (`check_slprop` / post-hint typing), not by phase 2.
  * With F* master, Core silently dropped the obligation for the `then`
    branch. This is the same symptom as §3.2: the `if` is a `match` on `bool`.
  * The file fails with the PR F* both with and without `--ext phase2_core`.
    It passes with master. So the PR's Core rewrite, not phase 2, is what now
    reports the obligation correctly.
* **The fix:** restate the length fact in the post, where it is provable. No
  client changed.

### 3.2 F* master's Core dropped branch guards of unannotated matches (old Core unsound, PR correct)

This is the same symptom as §3.1, found from the other direction.

* **Repro:** [IfJoinRefinedBranch.fst](https://github.com/FStarLang/FStar/blob/aa36780690f475789bde0324852891bceff2c833/pulse/test/bug-reports/IfJoinRefinedBranch.fst#L1-L22).
  Pulse's join of an `if` builds
  `pts_to res (match c = 2ul with true -> 0ul | false -> g c)`.
* **F* master's Core:**
  * It typed the match at its first branch's type.
  * It logged a subtyping guard for the other branch.
  * It then reported the match checked "with guard None": the branch guard was
    lost.
  * Master's unannotated-match rule:
    [Core.fst@285d2038e2 L1731–L1812](https://github.com/FStarLang/FStar/blob/285d2038e2e2f865caf57f962c9ddc4c4ca8d709/src/typechecker/FStarC.TypeChecker.Core.fst#L1731-L1812).
* **The PR's Core:** it keeps the guard, so the same program is rejected.
  * Reasons it fails: the false branch does not have type `{x == 0ul}`, and the
    program is ill-typed only because of the synthesized type.
* **The principled fix:** [`aa36780690`](#21-aa36780690-core-check-an-unannotated-match-argument-against-the-formals-type).
  Do not synthesize a type for such a match; check it against the expected
  type.

So the PR's Core is *more* sound than master's here. Every downstream failure
of this shape was a false alarm from the synthesized type, not a real bug, so
pal needed no change.

I did not pin down exactly *where* master's Core drops the guard. Its code
differs too much from the PR's to bisect. Anyone keeping master's Core alive
should look into it.

### 3.3 A latent PR bug: let-rec nest names bound after the function's binders (SMT encoding mismatch)

* **Exposed by:** ulib `FStar.List.Tot.Base.list_refb`
  ([ulib L570–L578](https://github.com/FStarLang/FStar/blob/b7cd6d4daa19eae8b34f754e961f47abc675db62/ulib/FStar.List.Tot.Base.fst#L570-L578)).
  It surfaced while fixing §2.2, which changed the shape of its query.
  * The function:
    `let rec list_refb #a #p (l:list a{for_all p l}) : l':list (x:a{p x}){length l == length l'}`.
  * The recursive call `hd :: list_refb #a #p tl` needs the type
    `list (x:a{p x})` of the call.
* **Cause:**
  * Phase-2 Core discharged the let-rec guard in an environment with the
    function's binders *first* and the names of the nest *after* them.
  * `Encode.encode_query`
    ([Encode.fst L2393–L2402](https://github.com/FStarLang/FStar/blob/b7cd6d4daa19eae8b34f754e961f47abc675db62/src/smtencoding/FStarC.SMTEncoding.Encode.fst#L2393-L2402))
    closes the query only over the trailing `Binding_var`s. Everything earlier
    becomes a `declare-fun` constant.
  * So `a` and `p` became constants, and the refinement `x:a{p x}` became a
    nullary `Tm_refine` symbol. It was unrelated to the quantified encoding of
    the same refinement in the typing axiom of `list_refb`.
  * The solver therefore could not use the type of the recursive call.
* **Why the PR as submitted still passed:** `list_refb` passed *by accident*.
  * The PR's let-rec guard began with the declared type's WF conjunct.
  * Because of that, `discharge` did not peel `forall a p l` off the guard, so
    the binders stayed quantified rather than becoming constants.
  * Once §2.2 moved that conjunct into its own query, the binders were peeled
    and the failure appeared.
* **The bug is in the PR binary itself:** it fails on a variant of `list_refb`
  with a trivially well-formed type. The regression test also fails with the
  PR binary.
* **Confirming the diagnosis:** adding the missing
  `HasType (list_refb a p tl) (list refine)` to the saved failing SMT goal
  made it unsat.
* **Fix:** [`486f8561c7`](#23-486f8561c7-phase-2-core-bind-the-names-of-a-let-rec-nest-before-the-functions-binders)
  pushes the nest first, as TcTerm does.
  * Regression test: [LetRecRefinedResultCall.fst](https://github.com/FStarLang/FStar/blob/486f8561c7c3a9d2c4e86a3cc11f3c5790f08428/tests/bug-reports/closed/LetRecRefinedResultCall.fst#L1-L13).
  * Visible effect: the expected termination errors now list the binders.

**Takeaway for the PR:** any phase-2 discharge environment must match TcTerm's
binding order, or refinements over binders silently stop matching their
axioms. This loses completeness, not soundness.

### 3.4 Custard's unit-binder inconsistency (pre-existing, exposed by phase 2)

* **What Custard did:**
  * `ty_of_typ` reads binders off the *normalized* arrow, so it kept
    `err:(if false then error_handler else unit)` as a unit parameter.
  * Call sites tested the *unreduced* sort, which is not syntactically `unit`,
    so they deleted the argument.
* **Why it surfaced now:** under TcTerm the stored sort carried a
  `unit <: eqtype` ascription that, by luck, made both paths agree. Phase-2
  Core stores the phase-1 term without the ascription.
* **The related bug:** definitions dropped unit binders while arrow types kept
  them. It had always existed; EverParse `SpecializeABC` probes only hit it
  once the first fix decided unit "up to reduction".
* **Fixes:** §2.5 and §2.7. Both produce KaRaMeL errors on real code
  (EverParse), so neither is cosmetic.

### 3.5 Exponential search in Core's relation checker (EverCDDL)

* EverParse `COSE.Format` relates long chains of definitions that differ
  (EverCDDL environments `env5` vs `env4`).
* On a guard-free failure, Core retried argument-wise, then by unfolding either
  side, then by a fallback. It revisited every level of the chain from every
  level above it.
  * `env6` did not finish in hours.
  * With `--ext phase2_core=off` it took 90 ms.
* Fix [`9a5fa7ed4b`](#26-9a5fa7ed4b-core-remember-guard-free-relation-failures-within-a-top-level-check)
  memoizes guard-free failures per top-level check. The key is (relation,
  terms, physical env, flags).
* **Soundness:** only failures without a guard are cached, so a success with a
  guard is never replaced by a cached failure.

### 3.6 Z3 runs that ignore the rlimit

Two hacl-pulse goals sent Z3 into loops that **ignored `--z3rlimit`**:

* [`92e35f3`](https://github.com/FStarLang/hacl-pulse/commit/92e35f3939a1460c970b33b92b5417cbf89f3b57) `Spec.K256.Freeze.freeze_ok`
* [`a83f48a`](https://github.com/FStarLang/hacl-pulse/commit/a83f48a34f84e3c12dbf263c5fc884aa87a75c94) `Spec.Bignum256.store_byte_ok`

Wall-clock time grew without bound and `#restart-solver` did not help. Whether
it happened depended on the solver's history (earlier queries in the same Z3
process). Both were fixed by stating the needed fact as a lemma in the shape
used. This is a Z3 issue, not an F* one, but phase 2 changes query shapes
enough to trigger it. A Z3 bug report with the logged queries may be
worthwhile.

### 3.7 Pulse files that failed with phase 2 off but passed on master

These failed with the PR F* even with `--ext phase2_core=off`, which pointed
at Core-from-Pulse and suggested spec WF exposures like §3.1.

| File | Outcome |
|---|---|
| hacl `Hacl.Impl.Sub:112` | genuine spec bug (§3.1) |
| AlgoStar `RabinKarp:374`, `Huffman.Impl:531` | pass with the final F* (fixed by §2.1/§2.2); **no spec issue** |
| hacl `Hacl.Impl.MLKEM.NTT:339` | passes after [`feeb7ba`](https://github.com/FStarLang/hacl-pulse/commit/feeb7ba07265a82b2618a559eeae6dd0c6290c1b), which only adds `assert`s spelling out the counter wrap in each branch of `intt_layer_impl` ([L333–L345](https://github.com/FStarLang/hacl-pulse/blob/feeb7ba07265a82b2618a559eeae6dd0c6290c1b/code/mlkem/Hacl.Impl.MLKEM.NTT.fst#L333-L345)), mirroring the existing `ntt_layer_impl`. The spec is unchanged, so this was proof brittleness, not a spec bug. Not root-caused further. |

### 3.8 Smaller observations

* **Vacuous decreases conjunct.**
  * Phase-2 let-rec queries start with a conjunct like
    `forall x a (b: nat{a << a}). a + b >= 0`.
  * The decreases refinement ends up on a binder as `a << a \/ (a === a /\ l << l)`,
    which makes the conjunct vacuously true.
  * It is harmless, since the declared type's WF is now checked separately
    (§2.2), but it is wasted solver work and suggests the `<<`-refined binder
    types are built in a slightly wrong context.
* **Branch goals are not independent.** Phase-2 guards for the two branches of
  an `if` are separate conjuncts, so Z3 assumes the then-goal while proving the
  else-goal.
  * In AlgoStar `RadixSort.Spec` ([`efae6a9`](https://github.com/FStarLang/AlgoStar/commit/efae6a9de4067b83a0dbbe6cf60ee28f2ee9fd91)),
    the then-goal's nonlinear `digit_sum` terms derailed the else branch.
  * TcTerm's guard shape differs. Generating `(c ==> G1) /\ (~c ==> G2)` with
    independent labels could avoid this.
* **Side conditions lose the postconditions of earlier calls.** Several
  workarounds share one cause: a refinement side condition that TcTerm proved
  *after* a lemma call is now a separate goal, proven *without* that call's
  postcondition in scope.
  * Examples:
    * pgc `uint_to_t (v src + i*8)` without `field_addr_fits`;
    * everparse `hi - lo > 0` without the shift lemmas;
    * kuiper warpCol bound.
  * Each needed an earlier `assert`, a refined type, or a helper lemma.
* **Matching loops through `FStar.UInt.to_vec`.** These appeared in everparse
  `BitFields` and pgc `MinorHeap`. The new query shapes let `Seq.append` index
  lemmas fire on `to_vec` unfoldings under fuel. Fixed with `--fuel 0` or by
  excluding `FStar.UInt.to_vec`/`FStar.BitVector` from the facts.
* **A redundant assert became harmful.** AlgoStar `ModExpLR.Impl`
  ([`56f33a1`](https://github.com/FStarLang/AlgoStar/commit/56f33a12a355fd23edc276ebd72075a2fe95f44f),
  [deleted line was L109](https://github.com/FStarLang/AlgoStar/blob/56f33a12a355fd23edc276ebd72075a2fe95f44f/autoclrs/ch31-number-theory/CLRS.Ch31.ModExpLR.Impl.fst#L106-L112)).
  `assert (bit == 1)` in the else branch of `if bit = 0` stalled arithmetic
  under `smt.arith.nl false`. Removing it fixed the proof.

---

## 4. Per-project workarounds

All are `Olympus-Change: fstar-regression-workaround` unless noted. Each
weakens nothing: they add asserts or lemmas, lower fuel, or raise rlimits
locally.

### 4.1 hacl-pulse ([compare](https://github.com/FStarLang/hacl-pulse/compare/bc7c41e429c021eb1f9ffb4396697788178fcf0e...49c09320c36cc80638220ee611debf481312df5c))

| Commit | Change | Lines |
|---|---|---|
| [`92e35f3`](https://github.com/FStarLang/hacl-pulse/commit/92e35f3939a1460c970b33b92b5417cbf89f3b57) | K256.Freeze: `proper → felem` lemma; Z3 ignored rlimit (§3.6) | [Spec.K256.Freeze.fst L324–L329](https://github.com/FStarLang/hacl-pulse/blob/92e35f3939a1460c970b33b92b5417cbf89f3b57/spec/Spec.K256.Freeze.fst#L324-L329), [L344](https://github.com/FStarLang/hacl-pulse/blob/92e35f3939a1460c970b33b92b5417cbf89f3b57/spec/Spec.K256.Freeze.fst#L344), [L350](https://github.com/FStarLang/hacl-pulse/blob/92e35f3939a1460c970b33b92b5417cbf89f3b57/spec/Spec.K256.Freeze.fst#L350) |
| [`5c171b3`](https://github.com/FStarLang/hacl-pulse/commit/5c171b319ea3138acdd5efa335d98a6ef63e5d9c) | **`minimal`**: `unsub` post well-formed (§3.1) | [Hacl.Impl.Sub.fst L109](https://github.com/FStarLang/hacl-pulse/blob/5c171b319ea3138acdd5efa335d98a6ef63e5d9c/lib/Hacl.Impl.Sub.fst#L109) |
| [`ae1f7e3`](https://github.com/FStarLang/hacl-pulse/commit/ae1f7e34669bf3e07ca5be1e56512da4d447a2f9) | Bytes `le_bytes_split`: product rearrangement | [Hacl.Spec.Bytes.fst L413–L440](https://github.com/FStarLang/hacl-pulse/blob/ae1f7e34669bf3e07ca5be1e56512da4d447a2f9/lib/Hacl.Spec.Bytes.fst#L413-L440) |
| [`9fad959`](https://github.com/FStarLang/hacl-pulse/commit/9fad95961c3f766dd6e54efc2b944c75e7f39d88) | Bignum52.Window: last step of `eval_windows` as lemma | [Spec.Bignum52.Window.fst L132–L142](https://github.com/FStarLang/hacl-pulse/blob/9fad95961c3f766dd6e54efc2b944c75e7f39d88/spec/Spec.Bignum52.Window.fst#L132-L142), [L169–L170](https://github.com/FStarLang/hacl-pulse/blob/9fad95961c3f766dd6e54efc2b944c75e7f39d88/spec/Spec.Bignum52.Window.fst#L169-L170) |
| [`80f3530`](https://github.com/FStarLang/hacl-pulse/commit/80f35302f8496e51fc429286866e193a99ddeda0) | Curve25519 `fexp_add`: unfold via lemma (history-dependent nlsat churn) | [Spec.Curve25519.fst L89–L99](https://github.com/FStarLang/hacl-pulse/blob/80f35302f8496e51fc429286866e193a99ddeda0/spec/Spec.Curve25519.fst#L89-L99) |
| [`feeb7ba`](https://github.com/FStarLang/hacl-pulse/commit/feeb7ba07265a82b2618a559eeae6dd0c6290c1b) | MLKEM.NTT `intt_layer_impl` counter wrap (§3.7) | [Hacl.Impl.MLKEM.NTT.fst L333–L345](https://github.com/FStarLang/hacl-pulse/blob/feeb7ba07265a82b2618a559eeae6dd0c6290c1b/code/mlkem/Hacl.Impl.MLKEM.NTT.fst#L333-L345) |
| [`5bf28a1`](https://github.com/FStarLang/hacl-pulse/commit/5bf28a1713f1473422404e94e0d4ba274a116b24) | Poly1305.Field: chain/ripple helper lemmas | [L552–L579](https://github.com/FStarLang/hacl-pulse/blob/5bf28a1713f1473422404e94e0d4ba274a116b24/spec/Spec.Poly1305.Field.fst#L552-L579), [L778–L797](https://github.com/FStarLang/hacl-pulse/blob/5bf28a1713f1473422404e94e0d4ba274a116b24/spec/Spec.Poly1305.Field.fst#L778-L797) |
| [`586e49e`](https://github.com/FStarLang/hacl-pulse/commit/586e49eaf64a7428be6f04cd7a3dae3f222a570c) | Bignum.Convert `from_le_body`: bridge load/index | [Hacl.Bignum.Convert.fst L179–L182](https://github.com/FStarLang/hacl-pulse/blob/586e49eaf64a7428be6f04cd7a3dae3f222a570c/code/bignum/Hacl.Bignum.Convert.fst#L179-L182) |
| [`100415e`](https://github.com/FStarLang/hacl-pulse/commit/100415e0fa78781f6527e455c6ae56db757c8dbd) | MLKEM.Encode: state shift amount | [Hacl.Impl.MLKEM.Encode.fst L126–L128](https://github.com/FStarLang/hacl-pulse/blob/100415e0fa78781f6527e455c6ae56db757c8dbd/code/mlkem/Hacl.Impl.MLKEM.Encode.fst#L126-L128) |
| [`26dcb18`](https://github.com/FStarLang/hacl-pulse/commit/26dcb18ed0ee0e58db2d96ab28356d9a7a0542b6) | Ed25519.Smul: bit-offset case split lemma | [Spec.Ed25519.Smul.fst L155–L158](https://github.com/FStarLang/hacl-pulse/blob/26dcb18ed0ee0e58db2d96ab28356d9a7a0542b6/spec/Spec.Ed25519.Smul.fst#L155-L158), [L181](https://github.com/FStarLang/hacl-pulse/blob/26dcb18ed0ee0e58db2d96ab28356d9a7a0542b6/spec/Spec.Ed25519.Smul.fst#L181) |
| [`a83f48a`](https://github.com/FStarLang/hacl-pulse/commit/a83f48a34f84e3c12dbf263c5fc884aa87a75c94) | Bignum256 `store_byte_ok`; Z3 ignored rlimit (§3.6) | [Spec.Bignum256.fst L564–L582](https://github.com/FStarLang/hacl-pulse/blob/a83f48a34f84e3c12dbf263c5fc884aa87a75c94/spec/Spec.Bignum256.fst#L564-L582) |
| [`3a7c8e1`](https://github.com/FStarLang/hacl-pulse/commit/3a7c8e1eed157ec4732c23193ab51857dda3c477) | SHA2: normalize `pow2 16` for `fits_at_least_16` | [Hacl.Hash.SHA2.fst L75–L83](https://github.com/FStarLang/hacl-pulse/blob/3a7c8e1eed157ec4732c23193ab51857dda3c477/code/hash/Hacl.Hash.SHA2.fst#L75-L83) |
| [`49c0932`](https://github.com/FStarLang/hacl-pulse/commit/49c09320c36cc80638220ee611debf481312df5c) | P256.Group `inf_shape_of`: zero products, `fsub c 0` | [Spec.P256.Group.fst L52–L54](https://github.com/FStarLang/hacl-pulse/blob/49c09320c36cc80638220ee611debf481312df5c/spec/Spec.P256.Group.fst#L52-L54), [L115–L126](https://github.com/FStarLang/hacl-pulse/blob/49c09320c36cc80638220ee611debf481312df5c/spec/Spec.P256.Group.fst#L115-L126) |

### 4.2 AlgoStar ([compare](https://github.com/FStarLang/AlgoStar/compare/14342137601285acb501058863b5d8eb62fb4c53...018870fa826ccda4ef945eb6763e789c8684a9d5))

All paths are under `autoclrs/`.

| Commit | Change | Lines |
|---|---|---|
| [`2637774`](https://github.com/FStarLang/AlgoStar/commit/263777490c5003b8f9dbe7ccf78a937e44a3e889) | Quickselect.Lemmas `count_range_eq` decomposition asserts (timed out at rlimit 5) | [L53–L56](https://github.com/FStarLang/AlgoStar/blob/263777490c5003b8f9dbe7ccf78a937e44a3e889/autoclrs/ch09-order-statistics/CLRS.Ch09.Quickselect.Lemmas.fst#L53-L56) |
| [`7a4e9fe`](https://github.com/FStarLang/AlgoStar/commit/7a4e9fe9309e2825ecf2b6745836d989db6e50e4) | Strassen.Lemmas `2 * half == rows a` | [L325](https://github.com/FStarLang/AlgoStar/blob/7a4e9fe9309e2825ecf2b6745836d989db6e50e4/autoclrs/ch04-divide-conquer/CLRS.Ch04.Strassen.Lemmas.fst#L325) |
| [`efae6a9`](https://github.com/FStarLang/AlgoStar/commit/efae6a9de4067b83a0dbbe6cf60ee28f2ee9fd91) | RadixSort.Spec base-case lemma (§3.8, branch goals) | [L589–L605](https://github.com/FStarLang/AlgoStar/blob/efae6a9de4067b83a0dbbe6cf60ee28f2ee9fd91/autoclrs/ch08-linear-sorting/CLRS.Ch08.RadixSort.Spec.fst#L589-L605), [L612–L620](https://github.com/FStarLang/AlgoStar/blob/efae6a9de4067b83a0dbbe6cf60ee28f2ee9fd91/autoclrs/ch08-linear-sorting/CLRS.Ch08.RadixSort.Spec.fst#L612-L620) |
| [`be723b2`](https://github.com/FStarLang/AlgoStar/commit/be723b23b9326ed39465b9de1ff7e30c4cbf6b2b) | InsertionSort.Rubric inner-invariant helper | [L193–L208](https://github.com/FStarLang/AlgoStar/blob/be723b23b9326ed39465b9de1ff7e30c4cbf6b2b/autoclrs/ch02-getting-started/CLRS.Ch02.InsertionSort.Rubric.fst#L193-L208), [L267](https://github.com/FStarLang/AlgoStar/blob/be723b23b9326ed39465b9de1ff7e30c4cbf6b2b/autoclrs/ch02-getting-started/CLRS.Ch02.InsertionSort.Rubric.fst#L267) |
| [`6720107`](https://github.com/FStarLang/AlgoStar/commit/67201074ead13959ed096f424b85504f7f1bf4ec) | Partition.Lemmas `transfer_*_slice` via `forall_intro` | [L45–L49](https://github.com/FStarLang/AlgoStar/blob/67201074ead13959ed096f424b85504f7f1bf4ec/autoclrs/ch07-quicksort/CLRS.Ch07.Partition.Lemmas.fst#L45-L49), [L64–L68](https://github.com/FStarLang/AlgoStar/blob/67201074ead13959ed096f424b85504f7f1bf4ec/autoclrs/ch07-quicksort/CLRS.Ch07.Partition.Lemmas.fst#L64-L68), [L83–L87](https://github.com/FStarLang/AlgoStar/blob/67201074ead13959ed096f424b85504f7f1bf4ec/autoclrs/ch07-quicksort/CLRS.Ch07.Partition.Lemmas.fst#L83-L87) |
| [`0e8e809`](https://github.com/FStarLang/AlgoStar/commit/0e8e809fd53b9510e9eaf624c232ad82a63e32a9) | ch08 helpers | [MultiDigit L999–L1021](https://github.com/FStarLang/AlgoStar/blob/0e8e809fd53b9510e9eaf624c232ad82a63e32a9/autoclrs/ch08-linear-sorting/CLRS.Ch08.RadixSort.MultiDigit.fst#L999-L1021), [Stability L170–L198](https://github.com/FStarLang/AlgoStar/blob/0e8e809fd53b9510e9eaf624c232ad82a63e32a9/autoclrs/ch08-linear-sorting/CLRS.Ch08.RadixSort.Stability.fst#L170-L198), [FullSort L205–L225](https://github.com/FStarLang/AlgoStar/blob/0e8e809fd53b9510e9eaf624c232ad82a63e32a9/autoclrs/ch08-linear-sorting/CLRS.Ch08.RadixSort.FullSort.fst#L205-L225), [DigitSortLemmas L518–L539](https://github.com/FStarLang/AlgoStar/blob/0e8e809fd53b9510e9eaf624c232ad82a63e32a9/autoclrs/ch08-linear-sorting/CLRS.Ch08.CountingSort.DigitSortLemmas.fst#L518-L539) |
| [`f44a405`](https://github.com/FStarLang/AlgoStar/commit/f44a40574121acc27305cef97826bdff7d4afc53) | ActivitySelection.Spec ordering assert | [L1028](https://github.com/FStarLang/AlgoStar/blob/f44a40574121acc27305cef97826bdff7d4afc53/autoclrs/ch16-greedy/CLRS.Ch16.ActivitySelection.Spec.fst#L1028) |
| [`a1b22d1`](https://github.com/FStarLang/AlgoStar/commit/a1b22d1e5f0c80bc443efbc291a06061856c9d02) | BFS.DistanceSpec, TopologicalSort.Impl.Defs lower fuel | [BFS L893](https://github.com/FStarLang/AlgoStar/blob/a1b22d1e5f0c80bc443efbc291a06061856c9d02/autoclrs/ch22-elementary-graph/CLRS.Ch22.BFS.DistanceSpec.fst#L893), [L991](https://github.com/FStarLang/AlgoStar/blob/a1b22d1e5f0c80bc443efbc291a06061856c9d02/autoclrs/ch22-elementary-graph/CLRS.Ch22.BFS.DistanceSpec.fst#L991); [TopoSort L948](https://github.com/FStarLang/AlgoStar/blob/a1b22d1e5f0c80bc443efbc291a06061856c9d02/autoclrs/ch22-elementary-graph/CLRS.Ch22.TopologicalSort.Impl.Defs.fst#L948), [L963](https://github.com/FStarLang/AlgoStar/blob/a1b22d1e5f0c80bc443efbc291a06061856c9d02/autoclrs/ch22-elementary-graph/CLRS.Ch22.TopologicalSort.Impl.Defs.fst#L963) |
| [`10f403a`](https://github.com/FStarLang/AlgoStar/commit/10f403a722c36628b214c2122e49c9a0fc396a71) | Kruskal.Impl call `index_bound` | [L560](https://github.com/FStarLang/AlgoStar/blob/10f403a722c36628b214c2122e49c9a0fc396a71/autoclrs/ch23-mst/CLRS.Ch23.Kruskal.Impl.fst#L560) |
| [`56f33a1`](https://github.com/FStarLang/AlgoStar/commit/56f33a12a355fd23edc276ebd72075a2fe95f44f) | ModExpLR.Impl drop redundant assert (§3.8) | [around L108](https://github.com/FStarLang/AlgoStar/blob/56f33a12a355fd23edc276ebd72075a2fe95f44f/autoclrs/ch31-number-theory/CLRS.Ch31.ModExpLR.Impl.fst#L106-L112) |
| [`b314c53`](https://github.com/FStarLang/AlgoStar/commit/b314c53074c70fd65c4f176476c517a7ac20b210) | KMP.Spec unfold `follow_fail` one step | [L236–L269](https://github.com/FStarLang/AlgoStar/blob/b314c53074c70fd65c4f176476c517a7ac20b210/autoclrs/ch32-string-matching/CLRS.Ch32.KMP.Spec.fst#L236-L269) |
| [`018870f`](https://github.com/FStarLang/AlgoStar/commit/018870fa826ccda4ef945eb6763e789c8684a9d5) | JarvisMarch.Lemmas lift local lemma to top level | [L267–L294](https://github.com/FStarLang/AlgoStar/blob/018870fa826ccda4ef945eb6763e789c8684a9d5/autoclrs/ch33-comp-geometry/CLRS.Ch33.JarvisMarch.Lemmas.fst#L267-L294), [L336](https://github.com/FStarLang/AlgoStar/blob/018870fa826ccda4ef945eb6763e789c8684a9d5/autoclrs/ch33-comp-geometry/CLRS.Ch33.JarvisMarch.Lemmas.fst#L336) |

### 4.3 kuiper ([compare](https://github.com/FStarLang/kuiper/compare/b5477e22c76982177077899eda4d967611db28fc...8487b55cfeba4d34ff7e9fa117be58266353e239))

| Commit | Change | Lines |
|---|---|---|
| [`bfeb5a0`](https://github.com/FStarLang/kuiper/commit/bfeb5a024aa9ed66adc172b18b5e27c95f27ccbe) | SPMM.StoreDense `offset_chunk` bound (nonlinear reassociation) | [L123–L125](https://github.com/FStarLang/kuiper/blob/bfeb5a024aa9ed66adc172b18b5e27c95f27ccbe/src/lib/sparse/Kuiper.Sparse.SPMM.StoreDense.fst#L123-L125) |
| [`66afc99`](https://github.com/FStarLang/kuiper/commit/66afc9940336a27f83a7be0e675ad3e7f8953487) | RowReduce: `1.0R /. rows /. nth >. 0.0R` helper lemma | [L845–L850](https://github.com/FStarLang/kuiper/blob/66afc9940336a27f83a7be0e675ad3e7f8953487/src/lib/kernel/Kuiper.Kernel.RowReduce.fst#L845-L850), [L930](https://github.com/FStarLang/kuiper/blob/66afc9940336a27f83a7be0e675ad3e7f8953487/src/lib/kernel/Kuiper.Kernel.RowReduce.fst#L930) |
| [`8a35d85`](https://github.com/FStarLang/kuiper/commit/8a35d85de28d432bccfbbd89c1fccd5bffaca942) | FlashAttention.KernelDesc: exclude `lemma_divides_product` (matching loop); index bounds lemma | [L135–L161](https://github.com/FStarLang/kuiper/blob/8a35d85de28d432bccfbbd89c1fccd5bffaca942/src/lib/kernel/Kuiper.Kernel.FlashAttention.KernelDesc.fst#L135-L161), [L208–L231](https://github.com/FStarLang/kuiper/blob/8a35d85de28d432bccfbbd89c1fccd5bffaca942/src/lib/kernel/Kuiper.Kernel.FlashAttention.KernelDesc.fst#L208-L231) |
| [`e7ae8f8`](https://github.com/FStarLang/kuiper/commit/e7ae8f8994886a00d59f25803aeedd16744588ae) | HReduce.Max: `1.0R /. nth >. 0.0R` helper lemma | [L859–L864](https://github.com/FStarLang/kuiper/blob/e7ae8f8994886a00d59f25803aeedd16744588ae/src/lib/kernel/Kuiper.Kernel.HReduce.Max.fst#L859-L864), [L927](https://github.com/FStarLang/kuiper/blob/e7ae8f8994886a00d59f25803aeedd16744588ae/src/lib/kernel/Kuiper.Kernel.HReduce.Max.fst#L927) |
| [`b8fc9c6`](https://github.com/FStarLang/kuiper/commit/b8fc9c67f63a5457c007aa969e424d2e07df02f6) | SPMM.Compute: row-step arithmetic lemma | [L1083–L1090](https://github.com/FStarLang/kuiper/blob/b8fc9c67f63a5457c007aa969e424d2e07df02f6/src/lib/sparse/Kuiper.Sparse.SPMM.Compute.fst#L1083-L1090), [L1109](https://github.com/FStarLang/kuiper/blob/b8fc9c67f63a5457c007aa969e424d2e07df02f6/src/lib/sparse/Kuiper.Sparse.SPMM.Compute.fst#L1109) |
| [`8487b55`](https://github.com/FStarLang/kuiper/commit/8487b55cfeba4d34ff7e9fa117be58266353e239) | GEMM.TensorCore: `warpCol < bn / tn` in its type (timed out at rlimit 300) | [L91–L99](https://github.com/FStarLang/kuiper/blob/8487b55cfeba4d34ff7e9fa117be58266353e239/src/lib/kernel/gemm/Kuiper.Kernel.GEMM.TensorCore.fst#L91-L99), [L533–L534](https://github.com/FStarLang/kuiper/blob/8487b55cfeba4d34ff7e9fa117be58266353e239/src/lib/kernel/gemm/Kuiper.Kernel.GEMM.TensorCore.fst#L533-L534) |

### 4.4 pulse-verified-gc ([compare](https://github.com/FStarLang/pulse-verified-gc/compare/ff83de91ce45f3ed97e2bc65a8484ac266bb445e...589bf2e88ed03bc489c0b638303d90730fdcb4a7))

| Commit | Change | Lines |
|---|---|---|
| [`efecc77`](https://github.com/FStarLang/pulse-verified-gc/commit/efecc775bcd4d2992d1902e4f91009a5e8388c71) | MinorHeap: fuel 0 / no `to_vec` facts for chain walks (matching loop, §3.8) | [L48](https://github.com/FStarLang/pulse-verified-gc/blob/efecc775bcd4d2992d1902e4f91009a5e8388c71/generational/spec/GC.Gen.MinorHeap.fst#L48), [L67](https://github.com/FStarLang/pulse-verified-gc/blob/efecc775bcd4d2992d1902e4f91009a5e8388c71/generational/spec/GC.Gen.MinorHeap.fst#L67), [L451](https://github.com/FStarLang/pulse-verified-gc/blob/efecc775bcd4d2992d1902e4f91009a5e8388c71/generational/spec/GC.Gen.MinorHeap.fst#L451), [L507](https://github.com/FStarLang/pulse-verified-gc/blob/efecc775bcd4d2992d1902e4f91009a5e8388c71/generational/spec/GC.Gen.MinorHeap.fst#L507) |
| [`e373789`](https://github.com/FStarLang/pulse-verified-gc/commit/e3737891cac88df16430446df7fd1fa339d7c7bd) | MinorCollectForwarding.Edges: local rlimit 20 (§3.8, side conditions) | [Edges.fsti L210–L212](https://github.com/FStarLang/pulse-verified-gc/blob/e3737891cac88df16430446df7fd1fa339d7c7bd/generational/spec/GC.Gen.MinorCollectForwarding.Edges.fsti#L210-L212), [L247](https://github.com/FStarLang/pulse-verified-gc/blob/e3737891cac88df16430446df7fd1fa339d7c7bd/generational/spec/GC.Gen.MinorCollectForwarding.Edges.fsti#L247) |
| [`66869ab`](https://github.com/FStarLang/pulse-verified-gc/commit/66869aba5c91f6086cf779c8b4850fc718796d1e) | MinorCollectForwarding: local rlimit 20, fuel 0 | [.fsti L207–L209](https://github.com/FStarLang/pulse-verified-gc/blob/66869aba5c91f6086cf779c8b4850fc718796d1e/generational/spec/GC.Gen.MinorCollectForwarding.fsti#L207-L209), [L245](https://github.com/FStarLang/pulse-verified-gc/blob/66869aba5c91f6086cf779c8b4850fc718796d1e/generational/spec/GC.Gen.MinorCollectForwarding.fsti#L245) |
| [`589bf2e`](https://github.com/FStarLang/pulse-verified-gc/commit/589bf2e88ed03bc489c0b638303d90730fdcb4a7) | MinorCollectForwarding: Ghost helper isolating `uint_to_t` side conditions | [L55–L58](https://github.com/FStarLang/pulse-verified-gc/blob/589bf2e88ed03bc489c0b638303d90730fdcb4a7/generational/spec/GC.Gen.MinorCollectForwarding.fst#L55-L58), [L713–L734](https://github.com/FStarLang/pulse-verified-gc/blob/589bf2e88ed03bc489c0b638303d90730fdcb4a7/generational/spec/GC.Gen.MinorCollectForwarding.fst#L713-L734), [L776–L777](https://github.com/FStarLang/pulse-verified-gc/blob/589bf2e88ed03bc489c0b638303d90730fdcb4a7/generational/spec/GC.Gen.MinorCollectForwarding.fst#L776-L777) |

### 4.5 everparse ([compare](https://github.com/project-everest/everparse/compare/56efa51529af7c96a6c76dc3f417607b12160665...071a7d4551c299d1a8de2b51452d67fd0722aaca))

| Commit | Change | Lines |
|---|---|---|
| [`071a7d4`](https://github.com/project-everest/everparse/commit/071a7d4551c299d1a8de2b51452d67fd0722aaca) | BitFields `get_bitfield_eq`: assert `0 < hi - lo` up front (`to_vec` matching loop, §3.8) | [LowParse.BitFields.fst L829](https://github.com/project-everest/everparse/blob/071a7d4551c299d1a8de2b51452d67fd0722aaca/src/lowparse/LowParse.BitFields.fst#L829) |

The EverParse **checker/extraction** failures were not proof failures. They
were the Core hang (§3.5) and the Custard unit-binder bugs (§3.4). Both were
fixed in F*, so EverParse itself needed only the one line above.

### 4.6 pal

No changes. Its three failures (`Func_lookup`, `Func_next_color`,
`Func_explicit_fallthrough`) were the if-join issue fixed in F* by §2.1.

---

## 5. Build infrastructure flakiness seen (unrelated to the PR)

* **FStar-ci:** intermittently fails with
  `stage2/dune/_build/default/tests/fstarc2_tests.exe: not found`. It looks
  like a race in the stage-2 unit-test rule and passes on rerun.
* **EverParse `goto_return` test:** a Makefile rule with two non-grouped
  targets can run the generator twice under parallel make (`Error 168`). It
  passed in the final build. The fix is to use a grouped target (`&:`).

---

## 6. Open questions and suggestions for the PR

1. **§3.2:** where exactly does F* master's Core lose the branch guard? It
   matters only if master's Core stays in use elsewhere, but it was a real
   unsoundness in Pulse spec checking (§3.1 shows real code relied on it).
2. **§3.3:** make sure every phase-2 discharge environment matches TcTerm's
   binding order. A debug-mode assertion that `encode_query` never turns a
   binder that occurs in a refinement into a constant would catch this class
   of bug.
3. **§3.8 vacuous `a << a` conjunct:** build the `<<`-refined binder types so
   that they do not end up as vacuous hypotheses.
4. **§3.8 branch-goal shape:** consider making the two branch guards
   independent, as TcTerm does, to avoid cross-branch interference in Z3.
5. **Side conditions:** many of the 35 workarounds share one shape, a
   refinement side condition proven without the postcondition of an earlier
   lemma call. Ordering these goals as TcTerm does would likely remove most of
   them.
6. **§3.6:** file a Z3 issue for the two rlimit-ignoring queries.

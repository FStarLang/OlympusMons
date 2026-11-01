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

* Round 1 (§1–§6): 7 commits were pushed to the PR branch: 4 fixes, 2
  Custard fixes and 1 Pulse library change.
* 1 project change fixes a **genuine spec bug**: an ill-formed Pulse
  postcondition in hacl-pulse that the old Core accepted.
* 35 round-1 project changes are proof-robustness workarounds: asserts, helper
  lemmas, and local fuel/rlimit/option changes. pal needed no change.
* Round 2 (§7): the latest PR commits, F* `master` and every project's
  `master`/`main` were merged. This exposed 4 more checker bugs, fixed in the
  PR (§7.2.1–§7.2.4), plus 2 proofs made fragile or re-checkable (§7.2.5–§7.2.6),
  and needed a few more project workarounds (§7.4).
* Round 3 (§7.8): F* `master` was merged; no project changes.
* Round 4 (§7.9): the latest `_phase2_core` (`e44d2dbbff`, including the
  consolidated match rule). 1 Pulse checker bug was fixed in the PR
  (`rewrite each` vs match `returns` annotations, §7.9.1). pal moved to
  `main`, and 13 more proof-robustness commits went into AlgoStar,
  pulse-verified-gc, kuiper and hacl-pulse.
* The full clean build of all 8 targets passes.

---

## 1. Result

### 1.1 Pins (`hashes.txt`, branch `olympus_phase2_core`)

| Project | Before (`main`) | Round 1 | Rounds 2–3 | Round 4 (current, §7.9) |
|---|---|---|---|---|
| FStar | `285d2038e2` (master) | [`b7cd6d4daa`](https://github.com/FStarLang/FStar/commit/b7cd6d4daa19eae8b34f754e961f47abc675db62) | [`6a1679b96e`](https://github.com/FStarLang/FStar/commit/6a1679b96eaecd89639c69dcaf5121ed0b60d6e0) (`_phase2_core`; round 2 `055a40ba30` + master `85d8ab69e0`, see §7.8) | [`e8d310d0e1`](https://github.com/FStarLang/FStar/commit/e8d310d0e1a2a8765a4c93c926953fffed0bda56) (`_phase2_core`) |
| everparse | `56efa51529` | [`071a7d4551`](https://github.com/project-everest/everparse/commit/071a7d4551c299d1a8de2b51452d67fd0722aaca) | [`c44e47f990`](https://github.com/project-everest/everparse/commit/c44e47f9904aa2d30d665d56dcb1c4cc3409e9fb) | `c44e47f990` (unchanged) |
| pal | `51b8c40fe3` | `51b8c40fe3` (unchanged) | [`58f168f7f1`](https://github.com/FStarLang/pal/commit/58f168f7f1e7e2fff50e348d415276a4edf168d6) (master, unchanged) | [`f5886f7153`](https://github.com/FStarLang/pal/commit/f5886f715367e5c6fbfcdfbc01b0b789a5993c13) (main) |
| kuiper | `b5477e22c7` | [`8487b55cfe`](https://github.com/FStarLang/kuiper/commit/8487b55cfeba4d34ff7e9fa117be58266353e239) | [`d2de7ad970`](https://github.com/FStarLang/kuiper/commit/d2de7ad97098d021d963908342fddfb3717dd6c7) | [`6dd8f5de14`](https://github.com/FStarLang/kuiper/commit/6dd8f5de142a708b77a3f51b26062c2631769560) |
| pulse-verified-gc | `ff83de91ce` | [`589bf2e88e`](https://github.com/FStarLang/pulse-verified-gc/commit/589bf2e88ed03bc489c0b638303d90730fdcb4a7) | [`3ee7803862`](https://github.com/FStarLang/pulse-verified-gc/commit/3ee7803862fec49d76f4c70e24a9cdda991308ab) | [`7b99af6598`](https://github.com/FStarLang/pulse-verified-gc/commit/7b99af6598f1023c40e2f8098dbd1c618521019e) |
| AlgoStar | `1434213760` | [`018870fa82`](https://github.com/FStarLang/AlgoStar/commit/018870fa826ccda4ef945eb6763e789c8684a9d5) | [`910f8785b9`](https://github.com/FStarLang/AlgoStar/commit/910f8785b9a8704790f0cb1f01ca2b3a8593d3b0) | [`3c85d5bd24`](https://github.com/FStarLang/AlgoStar/commit/3c85d5bd246b4f78f9949e1a34f73d9206f7ab2d) |
| hacl-pulse | `bc7c41e429` | [`49c09320c3`](https://github.com/FStarLang/hacl-pulse/commit/49c09320c36cc80638220ee611debf481312df5c) | [`385da8c6eb`](https://github.com/FStarLang/hacl-pulse/commit/385da8c6ebd5c830052b6608c78425715e9c473e) | [`eb8935ee6b`](https://github.com/FStarLang/hacl-pulse/commit/eb8935ee6b2efd9a1b00dd0e892b74fbefe7364c) |

Round 1 (OlympusMons [`2b8d8c1`](https://github.com/FStarLang/OlympusMons/commit/2b8d8c1e3b4f96b0d55c979638e468783ad2fabe)): each project's
`olympus_phase2_core` branch was its previously pinned commit plus the commits
listed in §4. Round 2: that branch merges the project's current `master`/`main`
and adds the commits in §7.3–§7.4. Each commit carries an `Olympus-Change:`
trailer:

* `minimal`: a genuine fix;
* `fstar-regression-workaround`: a proof made robust to the new checker.

### 1.2 Final clean build (`make -k CLEAN=1`; rounds 1–3 `-j128`, round 4 `-j24`)

| Target | Round 1 | Round 2 | Round 3 | Round 4 (current, §7.9) | Result |
|---|---|---|---|---|---|
| FStar | 10m51s | 15m15s | 14m39s | 14m44s | ✅ |
| FStar-ci | 52m | 1h08m53s | 1h16m00s | 23m28s | ✅ |
| everparse | 1h35m | 1h55m36s | 2h18m53s | 40m01s† | ✅ |
| pal | 25m | 38m44s | 47m35s | 19m43s | ✅ |
| kuiper | 1h07m | 1h28m20s | 1h48m26s | 1h04m47s | ✅ |
| pulse-verified-gc | 52m | 1h13m12s | 1h20m58s | 30m24s | ✅ |
| AlgoStar | 17m | 29m00s | 40m23s | 5m07s | ✅ |
| hacl-pulse | 1h10m | 1h36m36s | 1h55m57s | 1h15m14s | ✅ |

Round-2 and round-3 times are longer. The projects' `master`/`main` grew (e.g. kuiper's
new TensorCore2D kernels, EverParse's new 3D hash tests), and the machine was
shared with other jobs; the times were not investigated further.

Round 4 ran on a different, 24-core machine with `OLYMPUS_TIMEOUT=12h`, so its
times are not comparable with the earlier rounds. †everparse's first run in the
clean build failed once, in a 3D test (§7.9.4), and passed when re-run
incrementally; the time shown is the re-run.


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

---

## 7. Round 2: latest PR, F* master and project masters merged

In this round:

* the PR branch was brought up to date with the PR commits pushed after round 1;
* F* `master` was merged into the PR branch;
* each project's `master`/`main` was merged into its `olympus_phase2_core` branch;
* the full clean build was made to pass again.

§1 shows the state after this round. This section records how it got there.

### 7.1 F* (`_phase2_core`, [`b7cd6d4daa...055a40ba30`](https://github.com/FStarLang/FStar/compare/b7cd6d4daa19eae8b34f754e961f47abc675db62...055a40ba30c62f9c6abaa74c56d791f75eb5e206))

In order on the first-parent line:

| Commit | What |
|---|---|
| [`121177b969`](https://github.com/FStarLang/FStar/commit/121177b969c4cd3e04f1ff8c9305e6fdf9ef6a77) | merge F* `master` [`45697a089b`](https://github.com/FStarLang/FStar/commit/45697a089b84d93125ac739214adc8316fd5f844) |
| [`0f0822f009`](https://github.com/FStarLang/FStar/commit/0f0822f009848a388c39b7a8f9867afeaa9900ef) | **fix** typeclass resolution under an open context (§7.2.1) |
| [`827182b3b0`](https://github.com/FStarLang/FStar/commit/827182b3b01a6dfe06654d8e43436abb490a2dfc) | **fix** `dedup_vc` blocked by Core's labels (§7.2.2) |
| [`82b277a282`](https://github.com/FStarLang/FStar/commit/82b277a282c2efce3915a29e871461c3cf282b26) | **fix** the #4615 heuristic dropped preconditions' atoms (§7.2.3) |
| [`2a5a217d43`](https://github.com/FStarLang/FStar/commit/2a5a217d43ed21f17057055acd742774aafe3042) | merge of the PR commits pushed meanwhile; see the note below |
| [`d4dad4862b`](https://github.com/FStarLang/FStar/commit/d4dad4862b5339123b8caff6cc49571b0e9bdc90) | merge F* `master` [`629d22c5b5`](https://github.com/FStarLang/FStar/commit/629d22c5b54798e67234e3efc052d83871c3c56b) |
| [`3afe8c7f52`](https://github.com/FStarLang/FStar/commit/3afe8c7f52496bee93c8505b90b72cbf42864e68) | `tests/tactics/Postprocess.fst.output.expected`: gensym numbers shifted by the merge (`i#176`→`i#189`, `f#177`→`f#190`) |
| [`eb8dc8e48d`](https://github.com/FStarLang/FStar/commit/eb8dc8e48d1bf86252db62e8a5ab8dc0ccc40078) | **fix** a regression from `69b90c37eb`: let annotations checked before definitions (§7.2.4) |
| [`d8e8d01d41`](https://github.com/FStarLang/FStar/commit/d8e8d01d41b0f3350a316cdc2f482b07ec76acf8) | merge F* `master` [`72e5af4097`](https://github.com/FStarLang/FStar/commit/72e5af4097517dca6d54eddd62d861d5db0b87bd) (three Custard PRs: #4752, #4753, #4754) |
| [`aa8f57b17d`](https://github.com/FStarLang/FStar/commit/aa8f57b17d99530d871701db405dcae17e54b8e3) | `Pulse.Lib.PriorityQueue`: state a fragile nonlinear WF fact (§7.2.5) |
| [`1ff23d1f60`](https://github.com/FStarLang/FStar/commit/1ff23d1f60566f7eae219b39252ae623df71b72e) | merge the PR's [`fffa270f55`](https://github.com/FStarLang/FStar/commit/fffa270f558e7b7717e3022207c14f65f9d0cd1c) "Core: compute facts in the same pass as types" and [`a314b0967a`](https://github.com/FStarLang/FStar/commit/a314b0967ac0b682121c72435ce602a6bea89d5b); see the note below |
| [`055a40ba30`](https://github.com/FStarLang/FStar/commit/055a40ba30c62f9c6abaa74c56d791f75eb5e206) | merge F* `master` [`18c5d4a409`](https://github.com/FStarLang/FStar/commit/18c5d4a409a91e92dc968816305af1763b521e5b) (#4761, Custard: discard unused results before local liveness analysis) |

Note on [`2a5a217d43`](https://github.com/FStarLang/FStar/commit/2a5a217d43ed21f17057055acd742774aafe3042): it merges the PR commits pushed while this round was running:

* [`fd6aee436f`](https://github.com/FStarLang/FStar/commit/fd6aee436f1f44fb5052bd46ec16c90402191673)
* [`a27f2fdbaf`](https://github.com/FStarLang/FStar/commit/a27f2fdbaf71bd5be9a2be4f6e4e3c09b870d9fc) "Run synth_by_tactic proofs in Core"
* [`69b90c37eb`](https://github.com/FStarLang/FStar/commit/69b90c37eb27249e5f78964847f59f12680b895c) "Core: check let definitions bidirectionally, in one pass"
* [`07a25f0447`](https://github.com/FStarLang/FStar/commit/07a25f04472fc1ec9c8bbc06a9a8b36bbdb22105)

Each merge of `master` was clean except for the Postprocess gensym numbers.

Note on `1ff23d1f60`: `fffa270f55` rewrote `check_let_def` to return the definition's facts and dropped its cache insert. That conflicted with §7.2.4's `eb8dc8e48d`. The resolution keeps `fffa270f55`'s version and moves the universe check of the annotation after the definition, as `eb8dc8e48d` does: [Core.fst L3263–L3283](https://github.com/FStarLang/FStar/blob/055a40ba30c62f9c6abaa74c56d791f75eb5e206/src/typechecker/FStarC.TypeChecker.Core.fst#L3263-L3283).

### 7.2 Exposed checker bugs (all fixed in the PR)

#### 7.2.1 Typeclass goals under an open context were solved in arbitrary order ([`0f0822f009`](https://github.com/FStarLang/FStar/commit/0f0822f009848a388c39b7a8f9867afeaa9900ef))

**Exposed by:** kuiper `Kuiper.Kernel.GEMMGPU.Type.fst(70)`: "Could not solve typeclass constraint `can_approximate (chest2 et ?u ?u) …`".

**Cause:**

* The context had free uvars: a signature binder `eC : chest2 et ?u ?u`.
* Because of that, `gamma_has_free_uvars` treated every typeclass goal as open.
* Once `Defer_open` made no progress, the fallback solved all goals eagerly, in list order.
* That order flips each iteration. `can_approximate (chest2 et ?u ?u) …` could therefore be tried, and fail, before `has_pts_to (array2 et lC) (chest2 et ?u ?u)`, the goal that determines `?u`.
* Whether this happens depends on goal order, not on the PR. The new test fails on F* master and on the PR, at different functions.

**Fix:**

* A new intermediate pass, `Defer_open_typ`, only runs goals whose own type is closed (modulo fundep positions). The order is now `Defer_open` → `Defer_open_typ` → `Defer_none`.
* The transition reverses the list (`List.rev`) to keep the old parity. Without it, Bug2021's reported unresolved implicit changed.

**Where:**

* [Rel.fst L5682–L5691](https://github.com/FStarLang/FStar/blob/0f0822f009848a388c39b7a8f9867afeaa9900ef/src/typechecker/FStarC.TypeChecker.Rel.fst#L5682-L5691)
* [L5764–L5776](https://github.com/FStarLang/FStar/blob/0f0822f009848a388c39b7a8f9867afeaa9900ef/src/typechecker/FStarC.TypeChecker.Rel.fst#L5764-L5776)
* [L5861–L5867](https://github.com/FStarLang/FStar/blob/0f0822f009848a388c39b7a8f9867afeaa9900ef/src/typechecker/FStarC.TypeChecker.Rel.fst#L5861-L5867)
* test [tests/typeclasses/FundepsOpenCtx.fst](https://github.com/FStarLang/FStar/blob/0f0822f009848a388c39b7a8f9867afeaa9900ef/tests/typeclasses/FundepsOpenCtx.fst)

#### 7.2.2 `dedup_vc` did not look through Core's error labels ([`827182b3b0`](https://github.com/FStarLang/FStar/commit/827182b3b01a6dfe06654d8e43436abb490a2dfc))

**Cause:**

* PR Core wraps every guard it emits in a `Meta_labeled` node ("Could not prove post-condition").
* `dedup_vc` treated a labeled subterm as an atom.
* As a result, conjuncts restated by later preconditions were no longer dropped. An example is a lemma's `requires` that an earlier call had already proven.
* Master puts no labels there, so it deduplicates those conjuncts.

**Effect:** VCs were larger than on master. This contributed to AlgoStar and hacl timeouts.

**Fix:** descend through `Meta_labeled` and keep the label on what remains. See [Rel.fst L5246–L5254](https://github.com/FStarLang/FStar/blob/827182b3b01a6dfe06654d8e43436abb490a2dfc/src/typechecker/FStarC.TypeChecker.Rel.fst#L5246-L5254).

#### 7.2.3 The #4615 heuristic dropped atoms the query already assumes ([`82b277a282`](https://github.com/FStarLang/FStar/commit/82b277a282c2efce3915a29e871461c3cf282b26))

**Background:**

* PR commit [`1d92bae8fe`](https://github.com/FStarLang/FStar/commit/1d92bae8feb029d5b615ea5887d99f494fc40d49), the fix for FStarLang/FStar#4615, changed `split_goals_under`.
* A proven sibling conjunct that mentions a definition with a quantified body (`hides_quantifier`) is no longer assumed.

**Problem:**

* That also dropped atoms the query already had.
* In AlgoStar `RadixSort.Spec`, the lemma's own precondition `is_stable_sort_by_digit s_in s_out d base` is re-proven for a recursive call.
* The solver had the quantifier through the precondition anyway, but lost the ground atom, so goals that relied on it timed out.

**Bisect:**

* A temporary environment toggle disabling the heuristic fixed:
  * AlgoStar KMP.Bridge, DFS.Spec, Heap.ImplTest and RadixSort;
  * hacl `Spec.Bignum4` and `Spec.Ed25519.Group`.
* With the toggle, Bug4615 failed on z3 seeds 0, 3 and 5.

**Fix:**

* Record a hash of each quantifier-free conjunct of the query's squash-typed binders (preconditions) and of implication premises.
* Still assume a quantifier-hiding sibling when its encoding is one of them. Assuming a proven sibling is always sound.
* Bug4615 still passes on seeds 0–5.

**Where:**

* [ErrorReporting.fst L218–L234](https://github.com/FStarLang/FStar/blob/82b277a282c2efce3915a29e871461c3cf282b26/src/smtencoding/FStarC.SMTEncoding.ErrorReporting.fst#L218-L234)
* [L305–L308](https://github.com/FStarLang/FStar/blob/82b277a282c2efce3915a29e871461c3cf282b26/src/smtencoding/FStarC.SMTEncoding.ErrorReporting.fst#L305-L308)
* [L419–L422](https://github.com/FStarLang/FStar/blob/82b277a282c2efce3915a29e871461c3cf282b26/src/smtencoding/FStarC.SMTEncoding.ErrorReporting.fst#L419-L422)
* doc [core_typechecking.md L606–L610](https://github.com/FStarLang/FStar/blob/82b277a282c2efce3915a29e871461c3cf282b26/doc/ref/core_typechecking.md#L606-L610)

#### 7.2.4 `69b90c37eb` checked a let's annotation before its definition, dropping WF facts from the body ([`eb8dc8e48d`](https://github.com/FStarLang/FStar/commit/eb8dc8e48d1bf86252db62e8a5ab8dc0ccc40078))

This is the most interesting finding of the round. After merging the new PR commits, 7 hacl-pulse spec files regressed:

* `Spec.GF128.Poly:107`
* `Spec.RSAPSS:176`
* `Spec.Chacha20Poly1305:66`
* `Spec.Bignum4:646`
* `Spec.Ed25519.Group:547`
* `Spec.Bignum52.Window:129`
* `Spec.Poly1305.Vec:223`

So did 3 AlgoStar files.

**Bisect:** a build of `d4dad4862b` with `69b90c37eb` and `07a25f0447` reverted passes GF128.Poly, RSAPSS, Chacha20Poly1305, Bignum4 and Ed25519.Group.

**Cause:**

* `check_let_def` now ran `universe_of g lb.lbtyp` *before* checking the definition.
* Take a local lemma `aux (j:nat{j<16}) : Lemma (index a j == index b j)` whose body binds another annotated local lemma `f`. An example is hacl `Spec.GF128.Poly.bits_inj`: [Spec.GF128.Poly.fst L100–L110](https://github.com/FStarLang/hacl-pulse/blob/a1ce905862628825894611cb3e3d71a7e0a5b17b/spec/Spec.GF128.Poly.fst#L100-L110).
* Checking `aux`'s annotation first emitted its well-formedness guards (`j < 16 ==> j < length a`) closed over the arrow's binder, as a separate conjunct.
* `f`'s identical guards inside the body were then dropped as guard-cache hits (`guard`, via `raw_lookup_guard` with `context_included`).
* So the body's goals lost those facts as hypotheses:

  ```
  before 69b90c37eb:  forall j. WF(j) /\ (forall k. body(j,k))      -- WF(j) assumed for body
  with 69b90c37eb:    (forall j. WF(j)) /\ (forall j k. body(j,k))   -- only a quantified sibling
  ```

  A minimal repro of the VC shape is a 15-line file with assumed `bit`/`bit_at`, mirroring `bits_inj`.

**Why it times out:**

* In GF128 this exposed a Z3 matching loop.
* The `requires` `forall (i:nat). i < 128 ==> bit a i == bit b i` has no pattern. Z3 infers the triggers `HasTypeFuel MaxIFuel x nat` and `BoxInt_proj_0 x`, which produced 7227 instances in the failing query.
* With an explicit `{:pattern bit a i}` the same goal is unsat in 0.5s.

**Fix:**

* Check the definition first, then the annotation's universe, as before `69b90c37eb`. Both orders are sound. The definition's guard then carries the shared WF facts, in scope of the body.
* This fixes all 5 bisected hacl files and 2 of the 3 AlgoStar ones (UnionFind.Impl, RodCutting.Extended).

**Where:**

* [Core.fst L3239–L3240](https://github.com/FStarLang/FStar/blob/eb8dc8e48d1bf86252db62e8a5ab8dc0ccc40078/src/typechecker/FStarC.TypeChecker.Core.fst#L3239-L3240)
* [L3275–L3283](https://github.com/FStarLang/FStar/blob/eb8dc8e48d1bf86252db62e8a5ab8dc0ccc40078/src/typechecker/FStarC.TypeChecker.Core.fst#L3275-L3283)
* doc [core_typechecking.md L378–L384](https://github.com/FStarLang/FStar/blob/eb8dc8e48d1bf86252db62e8a5ab8dc0ccc40078/doc/ref/core_typechecking.md#L378-L384)

**Suggestion:** the guard cache can turn a hypothesis into a sibling conjunct depending on check order. The cache could prefer, or keep, the emission that is in scope of later goals. Alternatively, the cache hit could be skipped when the earlier emission was closed over binders the current context does not share.

#### 7.2.5 `Pulse.Lib.PriorityQueue`: a fragile nonlinear WF goal ([`aa8f57b17d`](https://github.com/FStarLang/FStar/commit/aa8f57b17d99530d871701db405dcae17e54b8e3))

This was not a checker bug.

**Symptom:** after the merge of master `72e5af4097` (`d8e8d01d41`), `grandparent_up_after_swap_child` failed at [PriorityQueue.fst L646](https://github.com/FStarLang/FStar/blob/d8e8d01d41b0f3350a316cdc2f482b07ec76acf8/pulse/lib/pulse/lib/Pulse.Lib.PriorityQueue.fst#L646).

**Diagnosis:**

* The goal lists (`--query_stats`) under `d4dad4862b` and `d8e8d01d41` are identical.
* Goal 10 is the well-formedness of `parent_idx (parent_idx child)`. It needs the nonlinear fact `(i-1)/2 < i`.
* That goal used 1.05 of its 5 rlimit units before and timed out after. This is Z3 variance on an identical query.

**Fix:** state that fact as the first conjunct of the `ensures`; see [L645](https://github.com/FStarLang/FStar/blob/aa8f57b17d99530d871701db405dcae17e54b8e3/pulse/lib/pulse/lib/Pulse.Lib.PriorityQueue.fst#L645). The file now needs at most 0.086 rlimit units.

Refining `parent_idx`'s result type to `r:nat{r < i}` instead broke `sift_down` (L1113), so that change was not kept.

#### 7.2.6 `synth_by_tactic` terms re-checked by Core: a tactic's SMT-discharged guards are no longer trusted ([`a27f2fdbaf`](https://github.com/FStarLang/FStar/commit/a27f2fdbaf71bd5be9a2be4f6e4e3c09b870d9fc))

This is a deliberate design change in the PR, but it has a cost for proof-producing tactics. EverParse's qd unit tests T7, T15_body, T20 and T40 failed with 4 errors each. Their modules are generated from [`share/everparse/tests/qd/unit/unittests.rfc`](https://github.com/project-everest/everparse/blob/c9cffd0858d20e5ea90265644d0d30c25e347b5e/share/everparse/tests/qd/unit/unittests.rfc); the T7 error is at `extracted/T7.fst` L234–L236. Each error is at a `validate_dsum`/`jump_dsum` call whose argument is `_ by (LP.dep_maybe_enum_destr_t_tac ())`.

**Bisect:** F* master `45697a089b` passes. `d4dad4862b` and later fail. The validator's VC has 2 goals on master and 20 on the PR.

**Cause:**

* The tactic ([LowParse.Spec.Tac.Sum L132–L150](https://github.com/project-everest/everparse/blob/c9cffd0858d20e5ea90265644d0d30c25e347b5e/lib/everparse/lowparse/LowParse.Spec.Tac.Sum.fst#L132-L150)) applies `dep_maybe_enum_destr_cons` once per enum case. It then closes the remaining goals with `T.compute (); T.smt ()`.
* Each step's invariant `u1 : squash (Cons? l2 /\ e == rev l1 @ l2)` is unified with the previous step's index, `list_append_rev_cons l1 (hd l2) (tl l2)`. That term's type, `rev l1 @ (x::l2) == rev (x::l1) @ l2`, does not mention `e`.
* On master, the tactic's own `compute; smt` justified each `squash G_k <: squash (Cons? l2 /\ e == …)` on the fully computed enum, and the result was trusted.
* Since `a27f2fdbaf`, Core re-checks the produced term "like any other term" ([core_typechecking.md L214–L220](https://github.com/FStarLang/FStar/blob/aa8f57b17d99530d871701db405dcae17e54b8e3/doc/ref/core_typechecking.md#L214-L220)). It must prove `e == rev l1' @ l2'` for step k+1 by plain SMT, without computation.
* The only hypotheses available are the `Cons?` WF facts and step 0's invariant. Steps 1 and 2 succeed through fuel 2; steps ≥3 and the final `Nil?` step fail.
* The jumper fails the same way in isolation. In the full file it appeared to pass only because its guards hit the guard cache after the validator's errors.

**Fix (EverParse, [`c9cffd0`](https://github.com/project-everest/everparse/commit/c9cffd0858d20e5ea90265644d0d30c25e347b5e)):**

* A new lemma `list_append_rev_cons_inv e l1 l2 u1 : Lemma (e == rev (hd l2 :: l1) @ tl l2)` takes the current invariant ([LowParse.Spec.Enum.fst L914–L926](https://github.com/project-everest/everparse/blob/c9cffd0858d20e5ea90265644d0d30c25e347b5e/lib/everparse/lowparse/LowParse.Spec.Enum.fst#L914-L926)).
* `maybe_enum_destr_cons` ([L935](https://github.com/project-everest/everparse/blob/c9cffd0858d20e5ea90265644d0d30c25e347b5e/lib/everparse/lowparse/LowParse.Spec.Enum.fst#L935)) and `dep_maybe_enum_destr_cons` ([L1073](https://github.com/project-everest/everparse/blob/c9cffd0858d20e5ea90265644d0d30c25e347b5e/lib/everparse/lowparse/LowParse.Spec.Enum.fst#L1073)) now index their continuation by it.
* Each step's invariant is now the type of the previous one, so Core's check is inductive. All 20 goals of `t7_validator` pass at ≤0.18 rlimit units.

**Question for the PR:** any tactic that discharges guards by computation (`T.compute (); T.smt ()`, `norm [delta]; trivial`, …) and then leaves the bare unification in the term will need the same treatment. Options are:

* document this as a migration note;
* let Core reuse a guard the tactic already proved by SMT;
* have Core apply the tactic's normalization to such guards.

### 7.3 Project merges

| Project | Merge | Notes |
|---|---|---|
| hacl-pulse | [`f100561`](https://github.com/FStarLang/hacl-pulse/commit/f100561f725a55e1fdb985d1b60fe3e99fa3b4b3) | master was **rewritten** (same commits under new hashes, plus `--codegen C`), so every file conflicted. Took master's tree and re-applied 12 of the 13 round-1 commits. The NTT workaround `feeb7ba` was dropped because master rewrote `intt_layer_impl`. |
| AlgoStar | [`8a412c9`](https://github.com/FStarLang/AlgoStar/commit/8a412c9801a9a38045c99059023cd2f254705bf6) | clean |
| kuiper | [`c22e016`](https://github.com/FStarLang/kuiper/commit/c22e0165fc6427291d66c7b66495c67b6cd5aff1) | conflicts in sparse SPMM. main restructured it: Load/LoadDense/LoadSparse/StoreDense were removed. Resolved in favour of main, which **lost round-1 hardening**; it is restored in `d2de7ad`. |
| pulse-verified-gc | [`382546f`](https://github.com/FStarLang/pulse-verified-gc/commit/382546f5dd5d4548b942acad03201953013ff93d) | clean |
| everparse | [`4d7dda5`](https://github.com/project-everest/everparse/commit/4d7dda55c0162e6e6b5a74c8f6f6c4f473321191) | clean |
| pal | — | no `olympus_phase2_core` changes; branch created at `58f168f7` |

**hacl-pulse master is not clean on its own under Olympus.** It was built with F* master `45697a089b` and Olympus's Z3 5.3.0. hacl-pulse has no Z3 pin and no CI. It fails at:

* `Spec.P256.Win{1,2,3}:83`
* `Spec.Poly1305.Vec:258`
* `Hacl.Chacha20.Vec512:619`
* `Hacl.Salsa20.Vec512:642`
* Error 173 in 6 files: F* master's `custard_c_closure_prologue` now takes one argument.

Several of the hacl changes below therefore fix master as much as they fix the PR.

### 7.4 Project changes in this round

All are `fstar-regression-workaround` unless marked **`minimal`**.

**hacl-pulse** ([compare](https://github.com/FStarLang/hacl-pulse/compare/f100561f725a55e1fdb985d1b60fe3e99fa3b4b3...385da8c6ebd5c830052b6608c78425715e9c473e)):

| Commit | Change | Lines |
|---|---|---|
| [`8d69133`](https://github.com/FStarLang/hacl-pulse/commit/8d69133a53fc7a4032b8f8b30263a71f4bd4f351) | **`minimal`**: port `CPrologue` closure attributes to the 1-argument `custard_c_closure_prologue` (17 files) | e.g. [Hacl.Vec512.fst L41](https://github.com/FStarLang/hacl-pulse/blob/8d69133a53fc7a4032b8f8b30263a71f4bd4f351/lib/Hacl.Vec512.fst#L41), [Hacl.AES.NI.fst L86](https://github.com/FStarLang/hacl-pulse/blob/8d69133a53fc7a4032b8f8b30263a71f4bd4f351/code/aes/Hacl.AES.NI.fst#L86) |
| [`9cda6da`](https://github.com/FStarLang/hacl-pulse/commit/9cda6da7252425879d405564a7a7ae131af67fcc) | P256.Win1/2/3: `e1_ok` also states `peq e1 (smul n g)` | [Spec.P256.Win1.fst L59](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/spec/Spec.P256.Win1.fst#L59), [Win2 L59](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/spec/Spec.P256.Win2.fst#L59), [Win3 L59](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/spec/Spec.P256.Win3.fst#L59) |
| 〃 | Chacha20.Vec512: per-case `qa/qb_collect`; named `tb_post`; `small_mod` for the chunk counter | [L508–L516](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/code/chacha/Hacl.Chacha20.Vec512.fst#L508-L516), [L602–L623](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/code/chacha/Hacl.Chacha20.Vec512.fst#L602-L623), [L645–L666](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/code/chacha/Hacl.Chacha20.Vec512.fst#L645-L666), [L990](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/code/chacha/Hacl.Chacha20.Vec512.fst#L990) |
| 〃 | Salsa20.Vec512: same as Chacha20.Vec512 | [L502–L510](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/code/salsa20/Hacl.Salsa20.Vec512.fst#L502-L510), [L596–L617](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/code/salsa20/Hacl.Salsa20.Vec512.fst#L596-L617), [L639–L660](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/code/salsa20/Hacl.Salsa20.Vec512.fst#L639-L660), [L984](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/code/salsa20/Hacl.Salsa20.Vec512.fst#L984) |
| 〃 | Salsa20.Vec256: `ob_fits`; `chunk_step` without the quadratic `S8.v_extensional` patterns | [L593–L595](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/code/salsa20/Hacl.Salsa20.Vec256.fst#L593-L595), [L629–L634](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/code/salsa20/Hacl.Salsa20.Vec256.fst#L629-L634), [L678](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/code/salsa20/Hacl.Salsa20.Vec256.fst#L678) |
| 〃 | Poly1305.Vec256: `fits16` for the block offset | [L1069–L1074](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/code/poly1305/Hacl.Poly1305.Vec256.fst#L1069-L1074), [L1185](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/code/poly1305/Hacl.Poly1305.Vec256.fst#L1185) |
| 〃 | P256.Exp: `E4.idx_of`, as `Hacl.Impl.Exp4.estep` does | [L117](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/code/p256/Hacl.P256.Exp.fst#L117) |
| 〃 | P256.Scalar: `sqr_pow2_step` | [L189–L196](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/code/p256/Hacl.P256.Scalar.fst#L189-L196), [L224–L226](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/code/p256/Hacl.P256.Scalar.fst#L224-L226) |
| 〃 | explicit arithmetic steps | [Blake2.Streaming L150](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/code/hash/Hacl.Hash.Blake2.Streaming.fst#L150), [MLDSA.Sample4 L138–L140](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/code/mldsa/Hacl.Impl.MLDSA.Sample4.fst#L138-L140), [MLKEM.Gen L482](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/code/mlkem/Hacl.Impl.MLKEM.Gen.fst#L482), [RSAPSS.Fermat L136–L137](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/spec/Spec.RSAPSS.Fermat.fst#L136-L137), [Bignum4.Window L126–L132](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/spec/Spec.Bignum4.Window.fst#L126-L132) |
| 〃 | `#restart-solver` | [MLKEM.Encode.Lemmas L204–L205](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/spec/Spec.MLKEM.Encode.Lemmas.fst#L204-L205), [K256.ECDSA.Correctness L199–L200](https://github.com/FStarLang/hacl-pulse/blob/9cda6da7252425879d405564a7a7ae131af67fcc/spec/Spec.K256.ECDSA.Correctness.fst#L199-L200) |
| [`a1ce905`](https://github.com/FStarLang/hacl-pulse/commit/a1ce905862628825894611cb3e3d71a7e0a5b17b) | Bignum52.Window `eval_win2`: same steps as Bignum4.Window | [L127–L133](https://github.com/FStarLang/hacl-pulse/blob/a1ce905862628825894611cb3e3d71a7e0a5b17b/spec/Spec.Bignum52.Window.fst#L127-L133) |
| 〃 | Poly1305.Vec `one_step`: expose the `block16` slice; `four_steps`: one assert per step | [L223–L224](https://github.com/FStarLang/hacl-pulse/blob/a1ce905862628825894611cb3e3d71a7e0a5b17b/spec/Spec.Poly1305.Vec.fst#L223-L224), [L253–L262](https://github.com/FStarLang/hacl-pulse/blob/a1ce905862628825894611cb3e3d71a7e0a5b17b/spec/Spec.Poly1305.Vec.fst#L253-L262) |
| 〃 | MLDSA.Encode.Lemmas: `nat_times_nat_is_nat` for `p.l * (32*e) >= 0` | [L332–L333](https://github.com/FStarLang/hacl-pulse/blob/a1ce905862628825894611cb3e3d71a7e0a5b17b/spec/Spec.MLDSA.Encode.Lemmas.fst#L332-L333) |
| 〃 | Ed25519.Group `curve_eq_gen`: explicit distributivity. It still failed after §7.2.4, although the revert build passed it. | [L547–L548](https://github.com/FStarLang/hacl-pulse/blob/a1ce905862628825894611cb3e3d71a7e0a5b17b/spec/Spec.Ed25519.Group.fst#L547-L548) |
| [`385da8c`](https://github.com/FStarLang/hacl-pulse/commit/385da8c6ebd5c830052b6608c78425715e9c473e) | MLDSA.Encode `pack_poly`: assert the unmasked coefficient's value before the masked one. The coefficient `c` is bound by an `if` on `signed`. This is new master code, and the assert timed out at rlimit 200. | [L186](https://github.com/FStarLang/hacl-pulse/blob/385da8c6ebd5c830052b6608c78425715e9c473e/code/mldsa/Hacl.Impl.MLDSA.Encode.fst#L186) |

**AlgoStar** ([compare](https://github.com/FStarLang/AlgoStar/compare/8a412c9801a9a38045c99059023cd2f254705bf6...910f8785b9a8704790f0cb1f01ca2b3a8593d3b0)); paths are under `autoclrs/`:

| Commit | Change | Lines |
|---|---|---|
| [`af8ccc9`](https://github.com/FStarLang/AlgoStar/commit/af8ccc9bd1218cfdecb818b7f59b79add356677e) | Heap.ImplTest: state `forall i<3. i=0 \/ i=1 \/ i=2` first | [ch06 L372](https://github.com/FStarLang/AlgoStar/blob/af8ccc9bd1218cfdecb818b7f59b79add356677e/autoclrs/ch06-heapsort/CLRS.Ch06.Heap.ImplTest.fst#L372) |
| 〃 | RadixSort.Spec: `assert (d == d0 + 1)` | [ch08 L620](https://github.com/FStarLang/AlgoStar/blob/af8ccc9bd1218cfdecb818b7f59b79add356677e/autoclrs/ch08-linear-sorting/CLRS.Ch08.RadixSort.Spec.fst#L620) |
| 〃 | ModExpLR.Impl: `mod2_cases` for the exponent bit | [ch31 L195–L196](https://github.com/FStarLang/AlgoStar/blob/af8ccc9bd1218cfdecb818b7f59b79add356677e/autoclrs/ch31-number-theory/CLRS.Ch31.ModExpLR.Impl.fst#L195-L196), [L289](https://github.com/FStarLang/AlgoStar/blob/af8ccc9bd1218cfdecb818b7f59b79add356677e/autoclrs/ch31-number-theory/CLRS.Ch31.ModExpLR.Impl.fst#L289) |
| 〃 | RabinKarp: two asserts and `distributivity_add_left` | [ch32 L362](https://github.com/FStarLang/AlgoStar/blob/af8ccc9bd1218cfdecb818b7f59b79add356677e/autoclrs/ch32-string-matching/CLRS.Ch32.RabinKarp.fst#L362), [L372–L373](https://github.com/FStarLang/AlgoStar/blob/af8ccc9bd1218cfdecb818b7f59b79add356677e/autoclrs/ch32-string-matching/CLRS.Ch32.RabinKarp.fst#L372-L373) |
| [`2c6186f`](https://github.com/FStarLang/AlgoStar/commit/2c6186f6905b077bb1721a6a8a7f39dce65a654d) | Huffman.Impl: assert the tick-count invariant conjunct before the loop body exits | [ch16 L528](https://github.com/FStarLang/AlgoStar/blob/2c6186f6905b077bb1721a6a8a7f39dce65a654d/autoclrs/ch16-greedy/CLRS.Ch16.Huffman.Impl.fst#L528), [L532](https://github.com/FStarLang/AlgoStar/blob/2c6186f6905b077bb1721a6a8a7f39dce65a654d/autoclrs/ch16-greedy/CLRS.Ch16.Huffman.Impl.fst#L532) |
| [`910f878`](https://github.com/FStarLang/AlgoStar/commit/910f8785b9a8704790f0cb1f01ca2b3a8593d3b0) | RabinKarp.Spec `hash_slice_lemma`: name the last character `c` and the inner hash `h`, and assert both unfolded hashes. The SMT query is byte-identical under `d4dad4862b` and the final binary. The old binary also fails it with `--z3refresh`, so this is Z3 session sensitivity. | [ch32 L177–L178, L181–L182, L184–L186](https://github.com/FStarLang/AlgoStar/blob/910f8785b9a8704790f0cb1f01ca2b3a8593d3b0/autoclrs/ch32-string-matching/CLRS.Ch32.RabinKarp.Spec.fst#L177-L186) |

The 5 AlgoStar chapters fixed by `af8ccc9` and by the F* fixes in §7.2.2 and §7.2.3 all passed with F* master.

**kuiper** — [`d2de7ad`](https://github.com/FStarLang/kuiper/commit/d2de7ad97098d021d963908342fddfb3717dd6c7). It restores the round-1 hardening lost in the merge and ports it to main's restructured files:

* the `chunk_*` bound lemmas: [Sparse.Array.PtsTo L17–L43](https://github.com/FStarLang/kuiper/blob/d2de7ad97098d021d963908342fddfb3717dd6c7/src/lib/sparse/Kuiper.Sparse.Array.PtsTo.fst#L17-L43), [SPMM.Defs L158–L162](https://github.com/FStarLang/kuiper/blob/d2de7ad97098d021d963908342fddfb3717dd6c7/src/lib/sparse/Kuiper.Sparse.SPMM.Defs.fst#L158-L162);
* the SMTPat bound lemmas: [SPMM.Barrier.fsti L24–L59](https://github.com/FStarLang/kuiper/blob/d2de7ad97098d021d963908342fddfb3717dd6c7/src/lib/sparse/Kuiper.Sparse.SPMM.Barrier.fsti#L24-L59);
* in the new `Sparse.LoadStore`: `divides_add_le`, `load_array_vec_chunk_end` and `load_array_vec_aligned` ([L16–L42](https://github.com/FStarLang/kuiper/blob/d2de7ad97098d021d963908342fddfb3717dd6c7/src/lib/sparse/Kuiper.Sparse.LoadStore.fst#L16-L42), [L53–L65](https://github.com/FStarLang/kuiper/blob/d2de7ad97098d021d963908342fddfb3717dd6c7/src/lib/sparse/Kuiper.Sparse.LoadStore.fst#L53-L65));
* in `Kernel.OnlineSoftmax`: `inv_of_pos_pat` ([L165–L172](https://github.com/FStarLang/kuiper/blob/d2de7ad97098d021d963908342fddfb3717dd6c7/src/lib/kernel/Kuiper.Kernel.OnlineSoftmax.fst#L165-L172), [L276–L283](https://github.com/FStarLang/kuiper/blob/d2de7ad97098d021d963908342fddfb3717dd6c7/src/lib/kernel/Kuiper.Kernel.OnlineSoftmax.fst#L276-L283));
* `Sparse.SPMM`: main's version with the hardening ported. The loop invariant uses `lslice` instead of `Seq.slice … (!idx * K)`, whose length subtyping timed out. See [L1394–L1407](https://github.com/FStarLang/kuiper/blob/d2de7ad97098d021d963908342fddfb3717dd6c7/src/lib/sparse/Kuiper.Sparse.SPMM.fst#L1394-L1407).

The typeclass failure in `GEMMGPU.Type` needed no kuiper change; §7.2.1 fixes it.

**pulse-verified-gc** — [`3ee7803`](https://github.com/FStarLang/pulse-verified-gc/commit/3ee7803862fec49d76f4c70e24a9cdda991308ab) (**`minimal`**, a main bug, not a PR issue):

* main's `b63dde3` dropped the `val`s of `minor_heap_size_sz` and `fwd_arr_size_sz` from `GC.Gen.Impl.MinorHeap.fsti`.
* KaRaMeL therefore no longer declared them in `GC_Gen_Impl.h`, and the hand-written `generational/snapshot/krmlinit.c` failed to compile.
* The `val`s are restored at [L44–L47 and L122–L125](https://github.com/FStarLang/pulse-verified-gc/blob/3ee7803862fec49d76f4c70e24a9cdda991308ab/generational/impl/GC.Gen.Impl.MinorHeap.fsti#L44-L47).

**everparse** ([compare](https://github.com/project-everest/everparse/compare/4d7dda55c0162e6e6b5a74c8f6f6c4f473321191...c44e47f9904aa2d30d665d56dcb1c4cc3409e9fb)):

* [`c9cffd0`](https://github.com/project-everest/everparse/commit/c9cffd0858d20e5ea90265644d0d30c25e347b5e) makes LowParse's enum destructors re-checkable by Core; see §7.2.6.
* [`c44e47f`](https://github.com/project-everest/everparse/commit/c44e47f9904aa2d30d665d56dcb1c4cc3409e9fb) merges the open everparse nightly PR project-everest/everparse#346 ("Update hashes and snapshots", branch `_dzomo_pr_39699891579`). That PR adapts EverParse to the same F* `master` changes that this round merged; see §7.6. It merged cleanly.
* [`707caaf`](https://github.com/project-everest/everparse/commit/707caaf4ad89d5071a478a8ee34d44737bfc4cdf) handles unrefinement. The new master code meets unrefinement (FStarLang/FStar#4586), which is on by default on the PR. An equality between refined byte sequences, or the implicit type of an intro lemma, is now inferred at the unrefined type. The commit states the intended types:
  * [CBOR.Spec.Raw.Valid.fsti L53, L233](https://github.com/project-everest/everparse/blob/707caaf4ad89d5071a478a8ee34d44737bfc4cdf/lib/everparse/cbor/spec/raw/CBOR.Spec.Raw.Valid.fsti#L53)
  * [CBOR.Spec.Raw.Valid.fst L60, L288](https://github.com/project-everest/everparse/blob/707caaf4ad89d5071a478a8ee34d44737bfc4cdf/lib/everparse/cbor/spec/raw/CBOR.Spec.Raw.Valid.fst#L60)
  * [CBOR.Spec.Raw.Nondet.fst L37](https://github.com/project-everest/everparse/blob/707caaf4ad89d5071a478a8ee34d44737bfc4cdf/lib/everparse/cbor/spec/raw/CBOR.Spec.Raw.Nondet.fst#L37)
  * [CBOR.Pulse.Raw.EverParse.Nondet.Gen.fst L75](https://github.com/project-everest/everparse/blob/707caaf4ad89d5071a478a8ee34d44737bfc4cdf/lib/everparse/cbor/pulse/raw/everparse/CBOR.Pulse.Raw.EverParse.Nondet.Gen.fst#L75)
  * [LowParse.Spec.BitVector.fst L174](https://github.com/project-everest/everparse/blob/707caaf4ad89d5071a478a8ee34d44737bfc4cdf/lib/everparse/lowparse/LowParse.Spec.BitVector.fst#L174)
  * [ASN1.Spec.Automata.fst L307](https://github.com/project-everest/everparse/blob/707caaf4ad89d5071a478a8ee34d44737bfc4cdf/src/ASN1/ASN1.Spec.Automata.fst#L307)

### 7.5 Z3 session sensitivity (most of the hacl workarounds)

Most of the hacl timeouts in this round are goals that are trivial in isolation but exhaust their rlimit in the F* session. Examples are `8*i >= 0`, `order - s < order` and `SZ.fits (16 * SZ.v g)`.

* The failing `Spec.MLKEM.Encode.Lemmas` query, replayed standalone, is unsat at about 0.25 rlimit units. In the session it exhausts rlimit 5.
* A `Salsa20.Vec256` query replayed standalone is unsat in 0.08s.
* In two cases the cause is quadratic quantifier instantiation from SMTPat lemmas in scope: `Hacl.Secret.UInt8.v_extensional` and `SizeT.fits_lte`.
* The PR's only `src/smtencoding` change against master is `ErrorReporting.fst`, so there is no single encoding switch to flip.
* `--z3refresh` and `#restart-solver` helped only sometimes. The workarounds therefore give the facts directly.

### 7.6 Toolchain changes from F* master

Two F* `master` changes merged in this round need toolchain changes outside the projects' proofs.

**GCC 15 for Cherry.**

* [`58b952f216`](https://github.com/FStarLang/FStar/commit/58b952f21644fe5e3b4b08e078437ccd5be19ad8) ("Cherry: tail groups via goto; require GCC 15 for musttail") makes [`ulib/c/cherry.h` L72](https://github.com/FStarLang/FStar/blob/aa8f57b17d99530d871701db405dcae17e54b8e3/ulib/c/cherry.h#L72) `#error` on any other compiler. As a result, FStar-ci's Cherry tests fail with Ubuntu 24.04's GCC 13/14.
* F*'s CI sets `CHERRY_CC=gcc-15 CHERRY_CXX=g++-15`, and `mk/test.mk` defaults `CHERRY_CC ?= $(CC)`.
* OlympusMons changes:
  * `scripts/build/FStar-ci.sh` exports these variables when `gcc-15`/`g++-15` are on `PATH` and the variables are unset.
  * `scripts/install-system-deps.sh` installs gcc-15/g++-15 from `ppa:ubuntu-toolchain-r/test`.
  * `README.md` lists GCC 15 as a prerequisite.

**F* writes JSON `.krml` files; Custard emits KaRaMeL `Private`.** Both
changes are in F* `master`, not in the PR. EverParse `master` pins F*
`6db6b296ad`, which has neither.

* [`69d0297e10`](https://github.com/FStarLang/FStar/commit/69d0297e1017879754bdf178f9f2c574f4f559eb) ("Custard: write .krml files as JSON instead of OCaml Marshal") made every EverParse krml step fail with `Fatal error: exception Failure("input_value: bad object")`. There were 35 occurrences, in 3D, CBOR, COSE, CDDL and the LowParse Pulse tests. EverParse's KaRaMeL, [`43709b90`](https://github.com/FStarLang/karamel/commit/43709b90c6e5a6aed13608d720cc38488abc82c6), selects the JSON reader by the `.json` extension.
* [`064c51c83c`](https://github.com/FStarLang/FStar/commit/064c51c83c804507e0057b87fc58aae0f63e3392) ("Custard: emit karamel Private for private / KrmlPrivate declarations") restores the legacy behaviour. As a result:
  * the COSE C and Rust snapshots lose the public `*_ugly` typedefs and the `*_left`/`*_right` conversions, which `FStar.Tactics.PrettifyType` tags `KrmlPrivate`; `COSE_Format_Inl`/`Inr` become `FStar_Pervasives_Inl`/`Inr`, and Rust's `evercddl_int_ugly_tags` becomes `either__uint64_t_uint64_t_tags`;
  * the 3D doc snapshot headers shrink similarly;
  * 3D's Low* `batch-cleanup-test` now also leaves `internal/ELF.h`, because `ELFTestGen` calls ELF's private `ElfValidateCoreElf` across translation units.
* I first patched these locally: a KaRaMeL with upstream's detect-JSON-by-content commits cherry-picked, and regenerated COSE snapshots. Then I found the EverParse nightly's open PR project-everest/everparse#346, which handles all of them. It moves EverParse's F* to `023bbb4bd6` (an ancestor of this PR's head), renames the generated files to `Custard.json`/`*.json` so the existing KaRaMeL pin works, expects `internal/ELF.h`, and regenerates the snapshots. I merged that PR instead and dropped my local changes.
* everparse `master` [`d09484dea`](https://github.com/project-everest/everparse/commit/d09484dea62824bf527dbdfcc1daa7e3f2b3accc) also removed `everparse-3d.exe`'s `KRML_EXE` lookup. The new `src/3d/tests` (hash checking) and `api_option_test.py` call it without `--karamel`, so it looks for `opt/karamel/out/bin/krml`, where EverParse's CI builds KaRaMeL. `scripts/build/everparse.sh` now symlinks `opt/karamel` to the KaRaMeL checkout that Olympus builds.

**GNU as for GCC 15 (local only).** The GCC 15 I used locally comes from the
`gcc:15` Docker image (Debian). It emits `.base64` directives, which
Ubuntu 24.04's binutils 2.42 cannot assemble, so I used that image's `as`
2.44 as well. A distribution GCC 15 is configured against the system
binutils and does not have this problem.

### 7.7 Process notes

* `make CLEAN=1 NOCHECKOUT=1` is **not** a clean build. The `git clean -xffd` that `CLEAN` implies runs in `checkout.sh`, which `NOCHECKOUT` skips. One such run reused stale `.checked` files and test outputs and reported spurious failures. The final build below used `make -k -j128 CLEAN=1`.
* Pins may name local, unpushed commits: `checkout.sh` checks with `git cat-file -e` before fetching.

### 7.8 Round 3: F* `master` `85d8ab69e0` merged

[`6a1679b96e`](https://github.com/FStarLang/FStar/commit/6a1679b96eaecd89639c69dcaf5121ed0b60d6e0)
merges F* `master` [`85d8ab69e0`](https://github.com/FStarLang/FStar/commit/85d8ab69e001bd0894a8765114c2a29360ea8111) into `_phase2_core`
([compare](https://github.com/FStarLang/FStar/compare/055a40ba30c62f9c6abaa74c56d791f75eb5e206...6a1679b96eaecd89639c69dcaf5121ed0b60d6e0)).
The PR had no new commits since round 2. Master's 18 new commits are Cherry and Custard backend work:
FStarLang/FStar#4759 (C precedence), FStarLang/FStar#4765, FStarLang/FStar#4766, FStarLang/FStar#4767 and FStarLang/FStar#4769. The merge was clean. The full clean
build passes with every project at its round-2 `olympus_phase2_core` commit,
unchanged; only the F* pin in `hashes.txt` moved.

### 7.9 Round 4: latest `_phase2_core` (`e44d2dbbff`) plus one Pulse fix

F* moved from `6a1679b96e` to
[`e8d310d0e1`](https://github.com/FStarLang/FStar/commit/e8d310d0e1a2a8765a4c93c926953fffed0bda56)
([compare](https://github.com/FStarLang/FStar/compare/6a1679b96eaecd89639c69dcaf5121ed0b60d6e0...e8d310d0e1a2a8765a4c93c926953fffed0bda56)).
First-parent commits:

| Commit | Content |
|---|---|
| `a6c758b3b8` | merges F* `master`: Pulse `-model.fst` implementation splits, `ArrayPtr.memcpy` API, Pulse closures, Cherry/Custard work, prelude additions (e.g. `List.Tot.length_acc`) |
| `85812abf7e` | Core: removes the unsound eta rules, adds `facts_exists`; `close_escaping` builds universe-instantiated existentials |
| `5b7d2d33f8` | comments |
| `d340d637bd` | Core: consolidated match rule; the elaborator annotates every un-annotated match with `returns` (`elaborated_match_returns`); arguments are checked against the formal's type |
| `e44d2dbbff` | drops unused pure lets (e.g. asserts) from branch equations in those annotations |
| [`e8d310d0e1`](https://github.com/FStarLang/FStar/commit/e8d310d0e1a2a8765a4c93c926953fffed0bda56) | **added in this round**: Pulse `rewrite each` up to match `returns` annotations (§7.9.1) |

F* `master` commits newer than the merge in `a6c758b3b8` were not merged.

#### 7.9.1 Checker bug: Pulse `rewrite each` stopped matching `if`s (EverParse)

* **Symptom:** `CBOR.Pulse.API.Nondet.Rust.fst(262)`: Error 228, `rewrite each` found no occurrence of its pattern.
* **Cause:** after `d340d637bd`, the same `if` gets a `returns` annotation for whatever type it is elaborated at, so the pattern and the occurrence in the context carry different `returns` types. `visit_and_rewrite` in `Pulse.Checker.AssertWithBinders` compares with `FStar.Reflection.TermEq.term_eq`, which compares `ret_opt` (unlike `U.eq_tm`, which ignores it).
* **Fix:** `strip_match_returns` erases match `returns` annotations; when the pattern contains any, the pattern and the candidates are compared after stripping.
* **Test:** `pulse/test/RewriteEachMatchReturns.fst` (fails before, passes after).

#### 7.9.2 Project changes

All commits are `Olympus-Change: fstar-regression-workaround`: proofs made robust by stating facts or adding helper lemmas, with no rlimit or fuel increases. No other goal became unprovable.

* **pal** ([compare](https://github.com/FStarLang/pal/compare/58f168f7f1e7e2fff50e348d415276a4edf168d6...f5886f715367e5c6fbfcdfbc01b0b789a5993c13)): fast-forwarded to `main`, which already adopted master's `-model.fst` split (`Pulse.Lib.C.Array`/`MaybeUninit`; the old layout fails with Error 129 because `friend Pulse.Lib.Reference` is no longer allowed). No new commits.
* **AlgoStar** ([compare](https://github.com/FStarLang/AlgoStar/compare/910f8785b9a8704790f0cb1f01ca2b3a8593d3b0...3c85d5bd246b4f78f9949e1a34f73d9206f7ab2d)):
  * `Quickselect.Lemmas`: helper `count_split3`;
  * `ExtendedGCD.Lemmas`: `abs_mul_nat` and explicit steps;
  * `Kruskal.Impl`: missing `index_bound wu wv n`.

  Quickselect also fails with `a6c758b3b8` alone (the master merge without the PR's commits), so it was perturbed by master's prelude additions.
* **pulse-verified-gc** ([compare](https://github.com/FStarLang/pulse-verified-gc/compare/3ee7803862fec49d76f4c70e24a9cdda991308ab...7b99af6598f1023c40e2f8098dbd1c618521019e)): `GC.Spec.Allocator.Lemmas.Part1.alloc_from_block_alloc_in_objects_part1` (lines 605–606) makes its two `objects` unfoldings and the header arithmetic explicit, with a new lemma `enumerated_hd_ge_start`. It now runs at fuel 0, rlimit 10 (was fuel 1, rlimit 25).
* **kuiper** ([compare](https://github.com/FStarLang/kuiper/compare/d2de7ad97098d021d963908342fddfb3717dd6c7...6dd8f5de142a708b77a3f51b26062c2631769560)):
  * `GEMM.TensorCore2D.Epilogue:161`: the fade step of the outer loop is proved with local lemmas (`em_fade_comb_tiles_flat`, `_next_row`).
  * `Sparse.SPMM:1579` (`kf_main`): the loop-exit residue arithmetic moves into small lemmas, and the `tile_mm` slice facts are stated before the call.

  `kf_main`/`kf_residue` still have goals that fail at the first rlimit and pass on F*'s fuel/ifuel retry: Z3 has trouble even with near-trivial facts in this very large context.
* **hacl-pulse** ([compare](https://github.com/FStarLang/hacl-pulse/compare/385da8c6ebd5c830052b6608c78425715e9c473e...eb8935ee6b2efd9a1b00dd0e892b74fbefe7364c)): seven commits; `dist/` is unchanged.

| File:line | Change |
|---|---|
| `Spec.Bignum4:646` | lemma `addw_upd2` keeps `srow` out of the `lemma_eq_intro` goal |
| `Spec.Bignum51.Window:171` | states `rad*0`, `pow2 0`, `s[0]` and one unfolding of `eval` |
| `Hacl.AES.GF128:366` | states `nxt / 128 < 2` and `carry == nxt / 128` |
| `Hacl.Impl.MLKEM.Gen:482` | helper `next_prefix` |
| `Hacl.Impl.MLDSA.VecRound:411` | generic `upto_step_gen` |
| `Hacl.Impl.Bignum4:158` | binds the loop counter after the loop (appeared once `Spec.Bignum4` passed) |
| `Hacl.Hash.SHA3.Sponge:580` | lemma `sz_not_lt` for the loop-exit test (§7.9.3) |

* **everparse:** unchanged; its only failure was §7.9.1.

#### 7.9.3 Z3 ignoring its rlimit (`Hacl.Hash.SHA3.Sponge`)

In the first build, one Z3 process ran for more than 2 hours on `squeeze_block_lanes` query 36 despite `rlimit 300`. This is the same phenomenon as §3.6. Bisecting:

* The query text is byte-identical under `a6c758b3b8` and `e44d2dbbff`, and passes in about 7s when checked alone.
* `d340d637bd` changes the shape of earlier VCs in the same module (check-against-formal for arguments assumes `SZ.fits (SZ.v r)` once instead of per argument; the two are logically equivalent). That changed Z3 history makes Z3 5.3.0 diverge on goal 6 of query 36.
* Replaying the logged query stream with `z3-5.3.0` alone reproduces the hang despite `:rlimit`. `--z3refresh` or `--z3seed 1` makes the original file pass.

So this is Z3 variance, not an encoding bug. The workaround states the loop-exit fact directly. A possible Pulse improvement: have `while` add the condition's `Pure` postcondition as a direct hypothesis at loop exit, since today it is reached only through two `reveal`s of an `erased (erased SZ.t)` witness.

#### 7.9.4 Toolchain and process notes

* pal now needs a newer Rust (edition 2024) than Ubuntu's cargo 1.75, plus `rustfmt` for its `format-check` target: `rustup` stable (1.99) with `rustup component add rustfmt`.
* `OLYMPUS_TIMEOUT=12h` was used on a 24-core machine; the default per-target timeouts assume a larger machine.
* **EverParse flake:** in the final clean build, `share/everparse/tests/3d/goto_return` failed once with Error 317: `output/GotoReturn.ExternalAPI.fsti.checked` was stale (digest mismatch) when the Custard extraction loaded it. The EverParse sources were unchanged from the first build, where this test passed, and the F* change between the two builds is Pulse-only (§7.9.1). The test passes when run on its own, and the incremental re-run of the whole everparse target passed. Most likely `everparse-3d` races between `--print_in_place` rewriting the generated `.fsti` and checking or extracting it.
* All project branches are fast-forwards of their round-3 tips; nothing was force-pushed.

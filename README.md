# OlympusMons
A repository of projects used for regression testing and continuous integration
of F*.

## The invariant

[`hashes.txt`](hashes.txt) records a commit of F* and of each project:

```
FStar:<commit>
everparse:<commit>
...
```

one `project:commit` per line (`#` starts a comment). **Every project builds
at its recorded commit, against the F* (with its Pulse and KaRaMeL) at the
recorded F* commit.** The projects' own pins of F*, KaRaMeL or Pulse
(submodules, nightly releases, hashes files, ...) are ignored, with one
exception: EverParse's code generation needs `krml` features that are only on
a KaRaMeL branch, not in F*'s KaRaMeL submodule, so EverParse uses the `krml`
of the KaRaMeL commit pinned in its own `opt/hashes.Makefile` (still with the
recorded F*).

| project | repository | what is built |
|---|---|---|
| FStar | [FStarLang/FStar](https://github.com/FStarLang/FStar) | stage 3 and a binary package; its CI target `make ci` |
| everparse | [project-everest/everparse](https://github.com/project-everest/everparse) | the targets of its Linux CI (`ci.yml`, `cbor.yml`), with the `krml` of its own KaRaMeL pin (see above) |
| pal | [FStarLang/pal](https://github.com/FStarLang/pal) | `make` and `make test`, as in its CI |
| kuiper | [FStarLang/kuiper](https://github.com/FStarLang/kuiper) | `make verify` only: its extraction needs its own patched F* and KaRaMeL |
| pulse-verified-gc | [FStarLang/pulse-verified-gc](https://github.com/FStarLang/pulse-verified-gc) | the steps of its CI (`verify.yml`) |
| AlgoStar | [FStarLang/AlgoStar](https://github.com/FStarLang/AlgoStar) | `make -C autoclrs`, as in its CI |
| hacl-pulse | [FStarLang/hacl-pulse](https://github.com/FStarLang/hacl-pulse) | `make` (verify, extract, compile, test); the committed `dist/` must be up to date |

The exact commands are in [`scripts/build/`](scripts/build).

When a project is not on its default branch's commit, it is usually on its
`olympus` branch, which has the changes needed to build with the recorded
F*. Each commit on an `olympus` branch says whether it is a minimal change
(`Olympus-Change: minimal`) or works around a significant regression in F*
(`Olympus-Change: fstar-regression-workaround`). These changes never admit
proofs or weaken specifications.

There is one Z3: the official release of the version that the recorded F*
uses by default (its `--z3version`, e.g. 5.3.0), downloaded by F*'s own
`.scripts/get_fstar_z3.sh` and installed in `_work/z3` as `z3` and `z3-<version>`
(see [`scripts/install-z3.sh`](scripts/install-z3.sh)). `_work/z3` comes
first in the PATH of every build. The projects that pin a Z3 version
(EverParse's `EVERPARSE_Z3_VERSION`, Kuiper's and pulse-verified-gc's
`Z3_VERSION`) are given this version instead. Any other Z3 (`z3-4.13.3`,
...) is shadowed in `_work/z3` by a stub that fails, so that a leftover pin
of another Z3 makes the build fail rather than silently use another Z3.

## Building

Prerequisites: [opam](https://opam.ocaml.org/), a C toolchain (with 32-bit
support, for EverParse's tests), clang/LLVM 20 and clang-format 20 (for pal),
Rust (for pal and EverParse), .NET 10 (for F*'s tests), and the GitHub CLI
`gh` (logged in) to clone the private repositories. On Ubuntu 24.04,
`sudo scripts/install-system-deps.sh` installs all of them but Rust, which is
best installed with [rustup](https://rustup.rs).

One-time setup, an opam switch (`olympus`) with the OCaml packages that F*
and the projects need, and the Z3 that F* uses:

```
scripts/setup.sh
```

Then:

```
make -k -j$(nproc)    # check out and build F* and all projects
make status           # summarize the results
make everparse        # check out and build F*, then one project
```

Everything happens in `_work/`: the clones are in `_work/src/<project>`,
Z3 is installed in `_work/z3` (again whenever F* is built), F* in
`_work/fstar`, and the log of each build is in
`_work/logs/<project>.log`. (In CI, `_work` is `~/olympus-work`, outside the
workspace, so that the jobs of a run share it; set `OLYMPUS_WORK` to move
it.)

Each build is given a time limit (`timeout_of` in
[`scripts/lib.sh`](scripts/lib.sh), overridden by `OLYMPUS_TIMEOUT`). A build
that exceeds it is killed, and what it was doing — the process tree, the load
and the free disk — is written to `_work/logs/<project>.diagnostics.log` just
before it is, so that a hang can be diagnosed afterwards. Nothing ever waits
for input: `git` is told not to prompt, so a repository that cannot be read
fails at once instead of blocking the build.

`make` checks out the recorded commits first, and refuses to do so over
changes to the tracked files of a tree. To build the trees in `_work/src` as
they are (for instance, while fixing a project), use `make NOCHECKOUT=1
<project>`; `FORCE=1` discards those changes instead. Builds are
incremental; `CLEAN=1` restores each tree to exactly the recorded commit --
discarding changes to tracked files as well as every untracked and ignored
file, F*'s KaRaMeL submodule included -- and rebuilds the F* package, for a
build from scratch (do this before committing a new `hashes.txt`). As it
rebuilds F*, do not use it while other builds are running.

Note that several of these projects regenerate committed files as they build
(hacl-pulse extracts into `dist/`, pulse-verified-gc into
`generational/snapshot/`), and so leave their tree with modified tracked
files. That is why `CLEAN=1`, and CI, put the trees back.

## Updating

To move F* (or a project) forward: change its commit in `hashes.txt`, run
`make -k -j$(nproc) CLEAN=1`, and fix any project that fails on (a new commit
of) its `olympus` branch. Only commit the new `hashes.txt` when everything
builds. The [nightly](#the-nightly) does this every night, with Copilot to
fix what breaks.

## Continuous integration

[`.github/workflows/build.yml`](.github/workflows/build.yml) builds everything
from scratch on every push to `main`, on every pull request (except from
forks), and on demand (`gh workflow run Build`). It is a graph of jobs:

```
                      /  FStar-ci   \
                     |   everparse   |
  Set up  ->  F*  -> |   pal         |  ->  Summary
                     |   kuiper      |
                      \  ...        /
```

* **Set up** checks that the runner can read every repository in
  `hashes.txt` (seconds, and before anything expensive), creates the opam
  switch and fetches Z3, and checks out every project. A repository it
  cannot read is reported straight away, but only F* stops the run: the
  rest are still worth building, and the job of the unreadable one fails on
  its own.
* **F\*** builds F* and installs it as the package that the rest use. It has
  the machine to itself, so it is given every core.
* One job **per target**, all depending on F* and running concurrently.
* **Summary** collects the results and fails if any target did not succeed.

Each target therefore has its own line in the run's graph, its own log (the
`log-<target>` artifact, and the tail of it in that job's summary), and its
own time limit (`timeout_of` in [`scripts/lib.sh`](scripts/lib.sh)). A build
that exceeds its limit is killed, but not before its log records the state of
the machine and the process tree underneath it, so that the run says *which*
command hung rather than only that something did. While a build runs it
reports what it is doing every couple of minutes, so a slow job can be told
from a stuck one as it happens.

`workflow_dispatch` takes two inputs: `targets`, to build only some of them
(`gh workflow run Build -f targets=hacl-pulse`), and `clean`, which can be
turned off to reuse the trees of the previous run when retrying one project.

The jobs of a run share one build tree (`~/olympus-work` on the runner), so a
run has the machine to itself; GitHub queues a new run behind the running
one, and keeps only the newest commit queued.

### The runners

A full build takes about 130 CPU-hours and a few hours even on a big machine,
far beyond GitHub's hosted runners for private repositories, so the workflow
runs on self-hosted runners labelled `olympus`. **Keep this repository
private**: on a public repository, anyone could run code on those runners
with a pull request.

A runner only ever runs one job at a time, so the number of runners
registered on the build machine is what decides how many of the per-project
jobs run at once. **Register one per project** (there are seven jobs after
F*); with a single runner they queue up and the build takes as long as all of
them put together.

To set up the machine, with Ubuntu 24.04 and 100 GB of free disk:

1. Create a user for the runners, and run `sudo scripts/install-system-deps.sh`
   (from a clone of this repository).
2. As that user, install Rust with [rustup](https://rustup.rs).
3. As that user, with `gh` logged in as an administrator of this repository:

   ```
   scripts/ci/add-runners.sh 8        # register 8 runners, as services
   scripts/ci/add-runners.sh --list   # what is registered, and running
   ```

   This registers the runners with the `olympus` label and installs each as a
   service, so they come back after a reboot. It is safe to re-run: runners
   that are already configured are left alone (and restarted if they are
   down). `--remove` unregisters the ones it created.
4. Give the builds read access to the private projects (hacl-pulse): either
   store a fine-grained personal access token (resource owner FStarLang,
   repository access to FStarLang/hacl-pulse only, permission "Contents:
   read-only") as the repository secret `OLYMPUS_GH_TOKEN`, or run `gh auth
   login` as the runners' user. The **Set up** job checks this in seconds and
   says so plainly; a project the runners cannot read fails at once, rather
   than hanging until its job runs out of time.

The opam switch is created (in the runner user's `~/.opam`) by the first
build. By default each per-project job uses a quarter of the machine's cores
and the F* job uses all of them; the repository variable `OLYMPUS_JOBS`
overrides this with a fixed number of parallel jobs for every job.

## The nightly

[`.github/workflows/nightly.yml`](.github/workflows/nightly.yml) keeps
OlympusMons current with F*, unattended. Every night (08:00 UTC, or on
demand: `gh workflow run Nightly`) it:

1. **Advances** F* to the tip of its `master`, and every other project to the
   tip of its `olympus` branch (or of its default branch, for those that have
   none yet). A project only moves forward. Nothing is written to `hashes.txt`
   yet. If nothing is newer, it stops.
2. **Builds** all of it from scratch, as the Build workflow does: the same
   job graph, in parallel, with a log per target. It uses a tree
   (`~/olympus-nightly-work`) and an opam switch (`olympus-nightly`) of its
   own, so a Build can run beside it.
3. **Triages.** If F* or F*'s own CI fails, it stops: that is for a person,
   and fixing the projects would be wasted. Otherwise each project that
   failed gets a **Fix** job, in parallel with the others.
4. **Fixes.** A Fix job runs the [Copilot CLI](https://github.com/github/copilot-cli)
   (autopilot, Claude Opus 5.5) once, in the tree of the failed build, with
   the failing log, the F* that changed, and the rules: no `admit`, `assume`,
   `magic`, `--lax`; no deleted or skipped lemmas or tests; no CI or pin
   changes. There is no budget and no retry: the agent builds the project
   as often as it needs to, until the build passes or it gives up. The job
   then checks that its last build did pass and that the change has none of
   the shortcuts above, and commits the change **locally**. Nothing is
   pushed.
5. **Verifies.** When all the Fix jobs have succeeded, each fixed project is
   **built again from scratch**, at the commit of its fix: what is recorded
   is a clean build of the commit, not of the tree Copilot left. (The projects
   are independent of each other, and the others were already built from
   scratch against this F*.)
6. **Publishes.** Only if everything built, it pushes each fix (never forced)
   to its project's `olympus` branch, which is created if there is none, and
   then commits the new `hashes.txt` to `main`. That last push is made with a
   token, so it starts a Build of it, as a final confirmation. Otherwise it
   fails, says why in its summary, and pushes and changes nothing anywhere:
   nothing reaches an `olympus` branch unless it has been built from scratch.

### Setting it up

Three repository secrets (Settings, Secrets and variables, Actions). A token
belongs to one organization, so pushing needs one per organization:

* `COPILOT_GITHUB_TOKEN`: a fine-grained personal access token with the
  "Copilot Requests" permission, of an account with Copilot.
* `OLYMPUS_PUSH_TOKEN_FSTARLANG`: a fine-grained personal access token
  (resource owner FStarLang) with "Contents: read and write" on this
  repository and on pal, kuiper, pulse-verified-gc, AlgoStar and hacl-pulse.
* `OLYMPUS_PUSH_TOKEN_PROJECT_EVEREST`: the same (resource owner
  project-everest), on everparse.

The push tokens are needed for publishing and for fixing. Which token pushes
to which repository is decided by its owner, in `push_token_var_of` in
[`scripts/lib.sh`](scripts/lib.sh); a project in a new organization needs a
line there and a secret.

The **Set up** job checks, in seconds, that the secrets exist and that each
can push to every repository it is for, and fails before anything expensive
if not. Without `COPILOT_GITHUB_TOKEN` the nightly still runs but only
reports, and does not publish a result that has failures. The runners need
Node.js only for the Fix jobs, which install it and the Copilot CLI
themselves.

`workflow_dispatch` takes: `fix` (off to only report), `publish` (off for a
dry run, which changes nothing), `force` (build even if nothing is newer),
`fstar_rev` (an F* branch or commit, instead of `master`) and `model`.

### What the credentials can do

Copilot runs with `--yolo` on the runner, and the builds run arbitrary
makefiles, so the tokens are kept apart: the Fix step has only the Copilot
token, and `scripts/nightly/fix.sh` hands Copilot nothing but that (no GitHub
login, no git configuration). The push tokens are used only by the Publish job,
and only by the commands that push, after everything has been built. Copilot
never commits or pushes; the workflow does that, after checking the result.

### Things to know

* `olympus` branches are advanced by the nightly only with fast-forward
  pushes. Every push is tried as a dry run first; if a branch moved while
  the nightly ran, nothing is pushed or recorded (each fix is kept as a patch
  in its `log-fix-<project>` artifact).
* The Fix jobs run on the machine that built the project, in its tree, so a
  fix's commit exists only there until Publish pushes it.
* Copilot has no cost cap here. The only limit is 12 hours for one agent, to
  guard against a hung session.
* FStar, everparse and pal have no `olympus` branch until the first time one
  of them needs a fix.
* Only the projects are fixed, never F*.

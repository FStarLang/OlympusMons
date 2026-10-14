# OlympusMons
A repository of projects used for regression testing and continuous integration
of F*.

## The invariant

[`hashes.txt`](hashes.txt) records a commit of Z3, of F* and of each project:

```
z3:<commit>
FStar:<commit>
everparse:<commit>
...
```

one `project:commit` per line (`#` starts a comment). **Every project builds
at its recorded commit, against the F* (with its Pulse and KaRaMeL) at the
recorded F* commit and the Z3 built from the recorded Z3 commit.** The
projects' own pins of F*, KaRaMeL, Pulse or Z3 (submodules, nightly
releases, hashes files, `--z3version` options, ...) are ignored, with one
exception: EverParse's code generation needs `krml` features that are only on
a KaRaMeL branch, not in F*'s KaRaMeL submodule, so EverParse uses the `krml`
of the KaRaMeL commit pinned in its own `opt/hashes.Makefile` (still with the
recorded F*).

| project | repository | what is built |
|---|---|---|
| z3 | [Z3Prover/z3](https://github.com/Z3Prover/z3) | the `z3` executable (release build), the only Z3 that F* and the projects can use (see below) |
| FStar | [FStarLang/FStar](https://github.com/FStarLang/FStar) | stage 3 and a binary package; its CI target `make ci` |
| everparse | [project-everest/everparse](https://github.com/project-everest/everparse) | the targets of its Linux CI (`ci.yml`, `cbor.yml`), with the `krml` of its own KaRaMeL pin (see above) |
| pal | [FStarLang/pal](https://github.com/FStarLang/pal) | `make` and `make test`, as in its CI |
| kuiper | [FStarLang/kuiper](https://github.com/FStarLang/kuiper) | `make verify` only: its extraction needs its own patched F* and KaRaMeL |
| pulse-verified-gc | [FStarLang/pulse-verified-gc](https://github.com/FStarLang/pulse-verified-gc) | the steps of its CI (`verify.yml`) |
| AlgoStar | [FStarLang/AlgoStar](https://github.com/FStarLang/AlgoStar) | `make -C autoclrs`, as in its CI |
| hacl-pulse | [FStarLang/hacl-pulse](https://github.com/FStarLang/hacl-pulse) | `make` (verify, extract, compile, test); the committed `dist/` must be up to date |

The exact commands are in [`scripts/build/`](scripts/build).

Z3 is installed in `_work/z3` as `z3` and as `z3-<version>` (e.g.
`z3-5.1.0`, the name under which F* looks for the Z3 of its `--z3version`),
and `_work/z3` comes first in the PATH of every build. The projects that
pin a Z3 version (EverParse's `EVERPARSE_Z3_VERSION`, Kuiper's and
pulse-verified-gc's `Z3_VERSION`) are given the version of this Z3 instead.
Any other Z3 that would be in the PATH (`z3-4.13.3`, ...) is shadowed in
`_work/z3` by a stub that fails, so that a leftover pin of another Z3 makes
the build fail rather than silently use another Z3.

When a project is not on its default branch's commit, it is usually on its
`olympus` branch, which has the changes needed to build with the recorded
F*. Each commit on an `olympus` branch says whether it is a minimal change
(`Olympus-Change: minimal`) or works around a significant regression in F*
(`Olympus-Change: fstar-regression-workaround`). These changes never admit
proofs or weaken specifications.

## Building

Prerequisites: [opam](https://opam.ocaml.org/), a C toolchain (with 32-bit
support, for EverParse's tests), CMake and Ninja (for Z3), clang/LLVM 20 and
clang-format 20 (for pal), Rust (for pal and EverParse), .NET 10 (for F*'s
tests), and the GitHub CLI `gh` (logged in) to clone the private
repositories. On Ubuntu 24.04, `sudo scripts/install-system-deps.sh` installs
all of them but Rust, which is best installed with
[rustup](https://rustup.rs).

One-time setup, an opam switch (`olympus`) with the OCaml packages that F*
and the projects need (Z3 is built from source by `make`):

```
scripts/setup.sh
```

Then:

```
make -k -j$(nproc)    # check out and build Z3, F* and all projects
make status           # summarize the results
make everparse        # check out and build Z3 and F*, then one project
```

Everything happens in `_work/`: the clones are in `_work/src/<project>`,
Z3 is installed in `_work/z3`, F* in `_work/fstar`, and the log of each build is in
`_work/logs/<project>.log`.

`make` checks out the recorded commits first, and refuses to do so over local
changes. To build the trees in `_work/src` as they are (for instance, while
fixing a project), use `make NOCHECKOUT=1 <project>`; `FORCE=1` discards
local changes instead. Builds are incremental; `CLEAN=1` deletes all
untracked and ignored files of the checked-out trees first (including F*'s
KaRaMeL submodule) and rebuilds the F* package, for a build from scratch (do
this before committing a new `hashes.txt`). As it rebuilds F*, do not use it
while other builds are running.

## Updating

To move Z3, F* (or a project) forward: change its commit in `hashes.txt`, run
`make -k -j$(nproc) CLEAN=1`, and fix any project that fails on (a new commit
of) its `olympus` branch. Only commit the new `hashes.txt` when everything
builds.

## Continuous integration

[`.github/workflows/build.yml`](.github/workflows/build.yml) builds everything
from scratch (`scripts/setup.sh`, then `make -k CLEAN=1`) on every push to
`main`, on every pull request (except from forks), and on demand (`gh workflow
run Build`). The job summary shows `make status` and the end of the log of
each failed build; the logs are also uploaded when the build fails. A new push
to a pull request cancels its running build.

A full build takes about 130 CPU-hours and a few hours even on a big machine,
far beyond GitHub's hosted runners for private repositories, so the workflow
runs on a self-hosted runner with the label `olympus`. **Keep this repository
private**: on a public repository, anyone could run code on that runner with
a pull request.

To set up a runner, on a machine with Ubuntu 24.04 and 100 GB of free disk:

1. Create a user for the runner, and run `sudo scripts/install-system-deps.sh`
   (from a clone of this repository).
2. As that user, install Rust with [rustup](https://rustup.rs).
3. In this repository's Settings > Actions > Runners, add a new self-hosted
   runner (Linux, x64) and follow the instructions as that user, adding
   `--labels olympus` to `./config.sh`. Then, rather than `./run.sh`, install
   it as a service: `sudo ./svc.sh install <user>` and `sudo ./svc.sh start`.
4. Give the builds read access to the private projects (hacl-pulse): either
   store a fine-grained personal access token (resource owner FStarLang,
   repository access to FStarLang/hacl-pulse only, permission "Contents:
   read-only") as the repository secret `OLYMPUS_GH_TOKEN`, or run `gh auth
   login` as the runner's user.

The opam switch is created (in the runner user's `~/.opam`) by the first
build. The repository variable `OLYMPUS_JOBS` sets the number of parallel jobs
(default: the number of cores).

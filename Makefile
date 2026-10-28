# OlympusMons: build every project at the commit recorded in hashes.txt,
# against the F* recorded there. See README.md.
#
#   make -k -j$(nproc)   check out and build everything (F* first)
#   make <project>       check out and build F*, then <project>
#   make status          summarize the last builds
#
#   NOCHECKOUT=1   build the trees in _work/src as they are (e.g. while fixing
#                  a project) instead of checking out the recorded commits
#   FORCE=1        discard changes to tracked files when checking out
#   CLEAN=1        restore the trees to the recorded commits when checking
#                  out -- discarding changes to tracked files and deleting
#                  untracked and ignored files (build products included) --
#                  and rebuild the F* package, to build from scratch
#
# Under a parallel make, all builds share its job slots.

PROJECTS := everparse pal kuiper pulse-verified-gc AlgoStar hacl-pulse atlas

.PHONY: all FStar FStar-ci $(PROJECTS) status
all: FStar FStar-ci $(PROJECTS)
	@scripts/status.sh

FStar:
	+@scripts/run.sh $@

FStar-ci $(PROJECTS): FStar
	+@scripts/run.sh $@

# Projects built against other projects' trees (deps_of in scripts/lib.sh).
atlas: everparse hacl-pulse

status:
	@scripts/status.sh

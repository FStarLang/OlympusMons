# OlympusMons: build every project at the commit recorded in hashes.txt,
# against the F* recorded there. See README.md.
#
#   make -k -j$(nproc)   check out and build everything (Z3 and F* first)
#   make <project>       check out and build Z3 and F*, then <project>
#   make status          summarize the last builds
#
#   NOCHECKOUT=1   build the trees in _work/src as they are (e.g. while fixing
#                  a project) instead of checking out the recorded commits
#   FORCE=1        discard local changes in _work/src when checking out
#   CLEAN=1        delete untracked and ignored files (build products
#                  included) when checking out, and rebuild the F*
#                  package, to build from scratch
#
# Under a parallel make, all builds share its job slots.

PROJECTS := everparse pal kuiper pulse-verified-gc AlgoStar hacl-pulse

.PHONY: all z3 FStar FStar-ci $(PROJECTS) status
all: z3 FStar FStar-ci $(PROJECTS)
	@scripts/status.sh

z3:
	+@scripts/run.sh $@

FStar: z3
	+@scripts/run.sh $@

FStar-ci $(PROJECTS): FStar
	+@scripts/run.sh $@

status:
	@scripts/status.sh

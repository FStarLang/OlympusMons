# OlympusMons: build every project at the commit recorded in hashes.txt,
# against the F* recorded there. See README.md.
#
#   make -k -j$(nproc)   check out and build everything (F* first)
#   make <project>       check out and build F*, then <project>
#   make status          summarize the last builds
#
#   NOCHECKOUT=1   build the trees in _work/src as they are (e.g. while fixing
#                  a project) instead of checking out the recorded commits
#   FORCE=1        discard local changes in _work/src when checking out
#
# Under a parallel make, all builds share its job slots.

PROJECTS := everparse pal kuiper pulse-verified-gc AlgoStar hacl-pulse

.PHONY: all FStar FStar-ci $(PROJECTS) status
all: FStar FStar-ci $(PROJECTS)
	@scripts/status.sh

FStar:
	+@scripts/run.sh $@

FStar-ci $(PROJECTS): FStar
	+@scripts/run.sh $@

status:
	@scripts/status.sh

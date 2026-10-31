# `make <task> [ARGS=...]` runs `mise run <task> [ARGS]`, so the mise tasks (mise.toml, mise-tasks/) stay the single source;
# `make help` lists them. Two exceptions: `make init` runs install.sh (works before mise exists), and
# apply/update/status/doctor/module/secret go through `djd`, which sets the locale and runs from $HOME.
MAKEFLAGS += --no-builtin-rules --no-print-directory
.SUFFIXES:
.DEFAULT_GOAL := help
MISE ?= $(shell command -v mise 2>/dev/null || echo $(HOME)/.local/bin/mise)
DJD_COMMANDS := apply update status doctor module secret

.PHONY: help init FORCE $(DJD_COMMANDS)
help:
	@$(MISE) tasks ls 2>/dev/null || echo "no mise tasks: run make init [ARGS=\"agent server ...\"], or mise trust this checkout"

init:
	./install.sh $(ARGS)

$(DJD_COMMANDS):
	@djd $@ $(ARGS)

Makefile: ;

# FORCE: run the task even when a file or directory of the same name exists (docs, tests)
%: FORCE
	@$(MISE) run $@ $(ARGS)

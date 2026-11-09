# `make <task> [ARGS=...]` runs `mise run <task> [ARGS]`, so the mise tasks (.mise/config.toml, .mise/tasks/) stay the single source;
# `make help` lists them. Two exceptions: `make init` runs install.sh (works before mise exists), and
# apply/update/status/doctor/module/secret go through `djd`, which sets the locale and runs from $HOME.
# ARGS reaches the recipes as an environment variable that the shell splits into words but never parses as commands,
# so ARGS='a b' passes two words and ARGS='x; cmd' passes "x;" and "cmd".
MAKEFLAGS += --no-builtin-rules --no-print-directory
.SUFFIXES:
.DEFAULT_GOAL := help
MISE ?= $(shell command -v mise 2>/dev/null || echo $(HOME)/.local/bin/mise)
# make init puts djd in ~/.local/bin, which the shell that ran it may not have on PATH yet
DJD ?= $(shell command -v djd 2>/dev/null || echo $(HOME)/.local/bin/djd)
DJD_COMMANDS := apply update status doctor module secret

.PHONY: help init FORCE $(DJD_COMMANDS)
export ARGS
# single-quoted for the shell, whatever the text holds
sq = '$(subst ','\'',$(1))'

help:
	@$(MISE) tasks ls 2>/dev/null || echo "no mise tasks: run make init [ARGS=\"agent server ...\"], or mise trust this checkout"

init:
	./install.sh $$ARGS

$(DJD_COMMANDS):
	@$(DJD) $@ $$ARGS

# an empty recipe, so make does not try the % rule below on the Makefile itself (it would run `mise run Makefile`)
Makefile: ;

# FORCE has no file and no recipe, so the % rule always runs: without it a file or directory named like a task would
# count as up to date, and make would skip the task
%: FORCE
	@$(MISE) run $(call sq,$@) $$ARGS

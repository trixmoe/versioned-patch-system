default: help

update: ## Update modules
	@./scripts/update.sh

nupdate: ## Update modules (no backup)
	@./scripts/update.sh -n

dirclean: ## Delete module directories
	@./scripts/cleandir.sh

save: ## Save patches
	@./scripts/save-patches.sh

save-one: ## Only saves a single patchset
	@./scripts/save-patches.sh --one

generic: ## Apply generic patches
	@./scripts/apply-patches.sh generic

specific: generic ## Apply patches for specific
	@./scripts/apply-patches.sh specific

specific2: generic ## Apply patches for specific2
	@./scripts/apply-patches.sh specific2

help: ## Show interactive help
	@printf "\e[1mVersioned Patch System\e[0m\n"
	@echo
	@echo   "Typical usage:"
	@printf "1. make \e[1;35mupdate\e[0m - Update all modules\n"
	@echo
	@printf "2. make \e[1;35mgeneric\e[0m - Only apply generic patches\n"
	@printf "2. make \e[1;35mspecific\e[0m - Apply generic + specific patches\n"
	@printf "2. make \e[1;35mspecific2\e[0m - Apply generic + specific2 patches\n"
	@echo
	@printf "3. make \e[1;35msave\e[0m - Save commits to patches\n"
	@echo
	@grep -E '^[a-z.A-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: *
.NOTPARALLEL:
.ONESHELL:

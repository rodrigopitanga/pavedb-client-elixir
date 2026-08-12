# (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com>
# SPDX-License-Identifier: Apache-2.0
#
# PaveDB Elixir Client — Makefile
#
# Basic usage:
#   make docs                    # generate the markdown API reference
#   make changelog               # preview the next changelog entry
#   make release                 # changelog + tarball, ready to tag
#
# VERSION is read from mix.exs and is the single source of truth. CI publishes
# to Hex from a v$(VERSION) tag; nothing here pushes or tags.

# GNU Make 4+ and bash 4+ required.
ifeq ($(shell uname -s),Darwin)
_MAKE_HINT := . macOS: `brew install make` and invoke as `gmake`
_BASH_HINT := . macOS: `brew install bash`
endif

_MAKE_MAJOR := $(firstword $(subst ., ,$(MAKE_VERSION)))
ifneq ($(filter 1 2 3,$(_MAKE_MAJOR)),)
$(error GNU Make >= 4 required (found $(MAKE_VERSION))$(_MAKE_HINT))
endif

SHELL := $(shell command -v bash)
ifeq ($(SHELL),)
$(error bash not found$(_BASH_HINT))
endif
_BASH_MAJOR := $(shell $(SHELL) -c 'echo $${BASH_VERSINFO[0]}' 2>/dev/null)
ifneq ($(filter 1 2 3,$(_BASH_MAJOR)),)
$(error bash >= 4 required (found bash $(_BASH_MAJOR).x at $(SHELL))$(_BASH_HINT))
endif

APP             := pavedb_client
VERSION         := $(shell sed -n 's/.*version: "\([^"]*\)".*/\1/p' mix.exs)

MIX             ?= mix
DOCS_DIR        ?= docs/reference
DIST_DIR        ?= dist
CHANGELOG       ?= CHANGELOG.md
RELEASE_REMOTE  ?= gitlab
TARBALL         := $(DIST_DIR)/$(APP)-$(VERSION).tar

# -------- help --------
.PHONY: help
help:
	@echo "$(APP) $(VERSION)"; \
	echo; \
	echo "  test                   Run the checks the CI test job runs"; \
	echo "  docs                   Generate the markdown API reference"; \
	echo "  bump                   Set the version in mix.exs (VERSION=x.y.z)"; \
	echo "  changelog              Preview the $(VERSION) entry (no write)"; \
	echo "  changelog-write        Prepend the $(VERSION) entry to $(CHANGELOG)"; \
	echo "  release                Bump, changelog, check, commit, and tag"; \
	echo "  release-tarball        Build $(TARBALL)"; \
	echo "  release-tarball-check  Build the tarball and verify its contents"; \
	echo "  release-tag-check      Assert CI_COMMIT_TAG matches v$(VERSION)"; \
	echo "  clean                  Remove generated docs and tarballs"

# -------- test --------
.PHONY: test
test:
	$(MIX) format --check-formatted
	$(MIX) compile --warnings-as-errors
	$(MIX) test

# -------- docs --------
.PHONY: docs
docs:
	$(MIX) docs --formatter markdown --output $(DOCS_DIR)

# -------- bump --------
.PHONY: bump
bump:
	@if [ -z "$(VERSION)" ]; then \
	  echo "Error: VERSION is not set. Usage: make bump VERSION=0.2.0"; \
	  exit 1; \
	fi
	@perl -0pi -e 's/^(\s*version: ")[^"]*(")/$${1}$(VERSION)$${2}/m' mix.exs
	@echo "Version in mix.exs is now $(VERSION)."

# -------- changelog --------
.PHONY: changelog
changelog:
	@CHANGELOG_PATH=- scripts/changelog.sh $(VERSION)

.PHONY: changelog-write
changelog-write:
	@CHANGELOG_PATH=$(CHANGELOG) scripts/changelog.sh $(VERSION)

# -------- release --------
# Only runs on tag pipelines, which already guarantee CI_COMMIT_TAG is set.
.PHONY: release-tag-check
release-tag-check:
	test "$(CI_COMMIT_TAG)" = "v$(VERSION)"

.PHONY: release-tarball
release-tarball: docs
	mkdir -p $(DIST_DIR)
	$(MIX) hex.build --output $(TARBALL)

.PHONY: release-tarball-check
release-tarball-check: release-tarball
	test -f $(TARBALL)
	rm -rf $(DIST_DIR)/unpacked
	$(MIX) hex.build --unpack --output $(DIST_DIR)/unpacked
	test -f $(DIST_DIR)/unpacked/$(DOCS_DIR)/api-reference.md

.PHONY: release
release:
	@if [ -n "$$(git status --porcelain)" ]; then \
	  echo "Working tree not clean"; exit 1; \
	fi
	@if git rev-parse "v$(VERSION)" >/dev/null 2>&1; then \
	  echo "Tag v$(VERSION) already exists"; exit 1; \
	fi
	@set -eE; \
	revert_changes() { \
	  echo "Reverting version bump and changelog..."; \
	  git checkout -- mix.exs $(CHANGELOG) 2>/dev/null || true; \
	}; \
	trap 'status=$$?; if [ "$$status" -ne 0 ]; then revert_changes; fi; exit $$status' ERR; \
	$(MAKE) bump VERSION=$(VERSION); \
	$(MAKE) changelog-write VERSION=$(VERSION); \
	$(MAKE) test VERSION=$(VERSION); \
	$(MAKE) release-tarball-check VERSION=$(VERSION); \
	git add mix.exs $(CHANGELOG); \
	if git diff --cached --quiet; then \
	  echo "Nothing to commit — release commit already exists."; \
	else \
	  git commit -m "chore(release): v$(VERSION)"; \
	fi; \
	git tag "v$(VERSION)"; \
	echo; \
	echo "Tagged v$(VERSION). Publish with:"; \
	echo "  git push $(RELEASE_REMOTE) $$(git rev-parse --abbrev-ref HEAD) v$(VERSION)"

# -------- clean --------
.PHONY: clean
clean:
	rm -rf $(DOCS_DIR) $(DIST_DIR)

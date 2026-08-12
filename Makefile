# (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com>
# SPDX-License-Identifier: Apache-2.0

APP := pavedb_client
VERSION := $(shell sed -n 's/.*version: "\([^"]*\)".*/\1/p' mix.exs)
DOCS_DIR := docs/reference
DIST_DIR := dist
TARBALL := $(DIST_DIR)/$(APP)-$(VERSION).tar

.PHONY: docs release-tag-check release-tarball release-tarball-check

docs:
	mix docs --formatter markdown --output $(DOCS_DIR)

# Only runs on tag pipelines, which already guarantee CI_COMMIT_TAG is set.
release-tag-check:
	test "$(CI_COMMIT_TAG)" = "v$(VERSION)"

release-tarball: docs
	mkdir -p $(DIST_DIR)
	mix hex.build --output $(TARBALL)

release-tarball-check: release-tarball
	test -f $(TARBALL)
	rm -rf $(DIST_DIR)/unpacked
	mix hex.build --unpack --output $(DIST_DIR)/unpacked
	test -f $(DIST_DIR)/unpacked/docs/reference/api-reference.md

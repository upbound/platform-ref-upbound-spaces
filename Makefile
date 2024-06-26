# Project Setup
PROJECT_NAME := platform-ref-upbound-spaces
PROJECT_REPO := github.com/upbound/$(PROJECT_NAME)

# NOTE(hasheddan): the platform is insignificant here as Configuration package
# images are not architecture-specific. We constrain to one platform to avoid
# needlessly pushing a multi-arch image.
PLATFORMS ?= linux_amd64
-include build/makelib/common.mk

# ====================================================================================
# Setup Kubernetes tools

UP_VERSION = v0.30.0
UP_CHANNEL = stable
UPTEST_VERSION = v0.11.1

-include build/makelib/k8s_tools.mk
# ====================================================================================
# Setup XPKG

# NOTE(jastang): Configurations deployed in Upbound do not currently follow
# certain conventions such as the default examples root or package directory.
XPKG_DIR = $(shell pwd)
XPKG_EXAMPLES_DIR = .up/examples
XPKG_IGNORE = .github/workflows/*.yml,.github/workflows/*.yaml,init/*.yaml,examples/*.yaml,.work/uptest-datasource.yaml,examples/**/*.yaml,gitops/*.yaml

XPKG_REG_ORGS ?= xpkg.upbound.io/upbound
# NOTE(hasheddan): skip promoting on xpkg.upbound.io as channel tags are
# inferred.
XPKG_REG_ORGS_NO_PROMOTE ?= xpkg.upbound.io/upbound
XPKGS = $(PROJECT_NAME)
-include build/makelib/xpkg.mk

CROSSPLANE_NAMESPACE = upbound-system
CROSSPLANE_ARGS = "--enable-usages"
-include build/makelib/local.xpkg.mk
-include build/makelib/controlplane.mk

# ====================================================================================
# Targets

# run `make help` to see the targets and options

# We want submodules to be set up the first time `make` is run.
# We manage the build/ folder and its Makefiles as a submodule.
# The first time `make` is run, the includes of build/*.mk files will
# all fail, and this target will be run. The next time, the default as defined
# by the includes will be run instead.
fallthrough: submodules
	@echo Initial setup complete. Running make again . . .
	@make

# Update the submodules, such as the common build scripts.
submodules:
	@git submodule sync
	@git submodule update --init --recursive

# We must ensure up is installed in tool cache prior to build as including the k8s_tools machinery prior to the xpkg
# machinery sets UP to point to tool cache.
build.init: $(UP)

# ====================================================================================
# End to End Testing

# This target requires the following environment variables to be set:
# $ export UPTEST_CLOUD_CREDENTIALS=$(echo "AWS='$(cat ~/.aws/credentials)'\nAZURE='$(cat ~/.azure/credentials.json)'\nGCP='$(cat ~/.gcloud/credentials.json)'\nSPACES='$(cat ~/.gcloud/key.json)'")
uptest: $(UPTEST) $(KUBECTL) $(KUTTL)
	@$(INFO) running automated tests
	@KUBECTL=$(KUBECTL) KUTTL=$(KUTTL) CROSSPLANE_NAMESPACE=$(CROSSPLANE_NAMESPACE) $(UPTEST) e2e "${UPTEST_EXAMPLE_LIST}" --data-source="${UPTEST_DATASOURCE_PATH}" --setup-script=test/setup.sh --default-timeout=4800 ${SKIP_DELETE} || $(FAIL)
	@$(OK) running automated tests

# This target requires the following environment variables to be set:
# $ export UPTEST_CLOUD_CREDENTIALS=$(echo "AWS='$(cat ~/.aws/credentials)'\nAZURE='$(cat ~/.azure/credentials.json)'\nGCP='$(cat ~/.gcloud/credentials.json)'\nSPACES='$(cat ~/.gcloud/key.json)'")
e2e: build controlplane.up local.xpkg.deploy.configuration.$(PROJECT_NAME) uptest

render:
	@indir="./examples"; \
	for file in $$(find $$indir -type f -name '*.yaml' ); do \
	    doc_count=$$(grep -c '^---' "$$file"); \
	    if [[ $$doc_count -gt 0 ]]; then \
	        continue; \
	    fi; \
	    COMPOSITION=$$(yq eval '.metadata.annotations."render.crossplane.io/composition-path"' $$file); \
	    FUNCTION=$$(yq eval '.metadata.annotations."render.crossplane.io/function-path"' $$file); \
	    if [[ "$$COMPOSITION" == "null" || "$$FUNCTION" == "null" ]]; then \
	        continue; \
	    fi; \
		crossplane beta render $$file $$COMPOSITION $$FUNCTION -x -r; \
	done

yamllint:
	@$(INFO) running yamllint
	@yamllint ./apis || $(FAIL)
	@$(OK) running yamllint

.PHONY: uptest e2e render yamllint

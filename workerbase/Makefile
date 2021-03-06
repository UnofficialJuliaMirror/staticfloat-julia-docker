include ../common.mk

# Build "dockerfiles" target that assembles all Dockerfiles
$(foreach f,$(HFS),$(eval $(call add_dep,dockerfiles,build/$(f)/Dockerfile)))

# Build "buildall" target that attempts to build every Dockerfile in the room,
# but only from the ones that our build architecture can manage.
BUILD_HFS=$(call arch_filt,$(BUILD_ARCH),$(HFS))
$(foreach f,$(BUILD_HFS),$(eval $(call add_dep,buildall,build-$(f))))

# Build "pushall" target that pushes up the result of "buildall"
$(foreach f,$(BUILD_HFS),$(eval $(call add_dep,pushall,push-$(f))))

# Search Dockerfiles for INCLUDE statements and add them to the make dependency
# tree, so that changing a dependency will rebuild the Dockerfile.
$(foreach f,$(HFS),$(eval $(call add_dep,build/$(f)/Dockerfile,$(shell ../dockerdeps ./$(f).Dockerfile))))

define build_dockerfile
# Running just `make build-ubuntu16_04-x86` will build that image
build-$(1): build/$(1)/Dockerfile
	$(DOCKER_BUILD) --pull -t $(call worker_tag_name,$(1)) "build/$(1)"

shell-$(1):
	docker run -ti $(call worker_tag_name,$(1))

# Running `make push-ubuntu16_04-x86` will upload that image to docker hub
push-$(1):
	docker push $(call worker_tag_name,$(1))

# This is how we build the actual Dockerfile
build/$(1)/Dockerfile: $(1).Dockerfile Makefile
	@if [ ! -f "$(1).Dockerfile" ]; then \
		echo "Target \"$(1)\" is invalid, recheck your spelling good sir."; \
		exit 1; \
	fi
	@mkdir -p "build/$(1)"
	@rm -f "build/$(1)/Dockerfile.tmp"
	@echo "$(1).Dockerfile"
	@../dockerchain ./$(1).Dockerfile > "build/$(1)/Dockerfile.tmp"
	@echo "## This file was autogenerated" > "build/$(1)/Dockerfile"
	@echo "# Do not edit directly; edit the .Dockerfile files" >> "build/$(1)/Dockerfile"
	@echo "#" >> "build/$(1)/Dockerfile"
	@echo "# To build this docker image via \`make\`, run \`make build-$(1)\` in the \`workerbase\` directory" >> "build/$(1)/Dockerfile"
	@echo "# To build this docker image manually, run \`docker build --pull -t $(call worker_tag_name,$(1)) .\`" >> "build/$(1)/Dockerfile"
	@echo >> "build/$(1)/Dockerfile"
	@cat "build/$(1)/Dockerfile.tmp" >> "build/$(1)/Dockerfile"
	@rm -f "build/$(1)/Dockerfile.tmp"
	@# Copy in any auxilliary scripts so they can be installed
	@cp lib/*.sh "build/$(1)/"
	@cp -R patches/ "build/$(1)/"
	@# On Windows, copy in the powershell scripts too
	@if [ -n "$(filter win%,$(1))" ]; then \
		cp lib/*.ps1 "build/$(1)/"; \
	fi
endef

$(foreach f,$(HFS),$(eval $(call build_dockerfile,$(f))))


clean:
	rm -rf build

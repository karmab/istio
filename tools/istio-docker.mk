## Copyright 2018 Istio Authors
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##     http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

.PHONY: docker

docker: docker.all

$(ISTIO_DOCKER) $(ISTIO_DOCKER_TAR):
	mkdir -p $@

.SECONDEXPANSION: #allow $@ to be used in dependency list

# static files/directories that are copied from source tree

PROXY_JSON_FILES:=pilot/docker/envoy_pilot.json \
                  pilot/docker/envoy_pilot_auth.json \
                  pilot/docker/envoy_mixer.json \
                  pilot/docker/envoy_mixer_auth.json

NODE_AGENT_TEST_FILES:=security/docker/start_app.sh \
                       security/docker/app.js

GRAFANA_FILES:=mixer/deploy/kube/conf/start.sh \
               mixer/deploy/kube/conf/grafana-dashboard.json \
               mixer/deploy/kube/conf/mixer-dashboard.json \
               mixer/deploy/kube/conf/pilot-dashboard.json \
               mixer/deploy/kube/conf/import_dashboard.sh

# note that "viz" is a directory rather than a file
$(ISTIO_DOCKER)/viz: mixer/example/servicegraph/js/viz | $(ISTIO_DOCKER)
	cp -r $< $(@D)

# generated content

# tell make which files are generated by gen-keys.sh
GENERATED_CERT_FILES:=istio_ca.crt istio_ca.key node_agent.crt node_agent.key
$(foreach TGT,$(GENERATED_CERT_FILES),$(eval $(ISTIO_DOCKER)/$(TGT): security/bin/gen-keys.sh | $(ISTIO_DOCKER); \
	OUTPUT_DIR=$(ISTIO_DOCKER) security/bin/gen-keys.sh))

# directives to copy files to docker scratch directory

# tell make which files are copied form go/out
DOCKER_FILES_FROM_ISTIO_OUT:=pilot-test-client pilot-test-server pilot-test-eurekamirror \
                             pilot-discovery pilot-agent sidecar-injector servicegraph mixs \
                             istio_ca node_agent
$(foreach FILE,$(DOCKER_FILES_FROM_ISTIO_OUT), \
        $(eval $(ISTIO_DOCKER)/$(FILE): $(ISTIO_OUT)/$(FILE) | $(ISTIO_DOCKER); cp $$< $$(@D)))

# tell make which files are copied from the source tree
DOCKER_FILES_FROM_SOURCE:=pilot/docker/prepare_proxy.sh docker/ca-certificates.tgz \
                          $(PROXY_JSON_FILES) $(NODE_AGENT_TEST_FILES) $(GRAFANA_FILES)
$(foreach FILE,$(DOCKER_FILES_FROM_SOURCE), \
        $(eval $(ISTIO_DOCKER)/$(notdir $(FILE)): $(FILE) | $(ISTIO_DOCKER); cp $(FILE) $$(@D)))

# This block exists temporarily.  These files need to go in a certs/ subdir, though
# eventually the dockerfile should be changed to not used the subdir, in which case
# the files listed in this section can be added to the preceeding section.
# The alternative is to generate new certs (as described by the readme in cert/ )
$(ISTIO_DOCKER)/certs: ; mkdir -p $@
DOCKER_CERTS_FILES_FROM_SOURCE:=pilot/docker/certs/cert.crt pilot/docker/certs/cert.key
$(foreach FILE,$(DOCKER_CERTS_FILES_FROM_SOURCE), \
        $(eval $(ISTIO_DOCKER)/certs/$(notdir $(FILE)): $(FILE) | $(ISTIO_DOCKER)/certs; cp $(FILE) $$(@D)))

# pilot docker images

docker.app: $(ISTIO_DOCKER)/pilot-test-client $(ISTIO_DOCKER)/pilot-test-server \
            $(ISTIO_DOCKER)/certs/cert.crt $(ISTIO_DOCKER)/certs/cert.key
docker.eurekamirror: $(ISTIO_DOCKER)/pilot-test-eurekamirror
docker.pilot:        $(ISTIO_DOCKER)/pilot-discovery
docker.proxy docker.proxy_debug: $(ISTIO_DOCKER)/pilot-agent
$(foreach FILE,$(PROXY_JSON_FILES),$(eval docker.proxy docker.proxy_debug: $(ISTIO_DOCKER)/$(notdir $(FILE))))
docker.proxy_init: $(ISTIO_DOCKER)/prepare_proxy.sh
docker.sidecar_injector: $(ISTIO_DOCKER)/sidecar-injector

PILOT_DOCKER:=docker.app docker.eurekamirror docker.pilot docker.proxy \
              docker.proxy_debug docker.proxy_init docker.sidecar_injector
$(PILOT_DOCKER): pilot/docker/Dockerfile$$(suffix $$@) | $(ISTIO_DOCKER)
	$(DOCKER_SPECIFIC_RULE)

# mixer/example docker images

# Note that Dockerfile and Dockerfile.debug are too generic for parallel builds
SERVICEGRAPH_DOCKER:=docker.servicegraph docker.servicegraph_debug
$(SERVICEGRAPH_DOCKER): mixer/example/servicegraph/docker/Dockerfile$$(if $$(findstring debug,$$@),.debug) \
		$(ISTIO_DOCKER)/servicegraph $(ISTIO_DOCKER)/viz | $(ISTIO_DOCKER)
	$(DOCKER_GENERIC_RULE)

# mixer docker images

# Note that Dockerfile and Dockerfile.debug are too generic for parallel builds
MIXER_DOCKER:=docker.mixer docker.mixer_debug
$(MIXER_DOCKER): mixer/docker/Dockerfile$$(if $$(findstring debug,$$@),.debug) \
		$(ISTIO_DOCKER)/ca-certificates.tgz $(ISTIO_DOCKER)/mixs | $(ISTIO_DOCKER)
	$(DOCKER_GENERIC_RULE)

# security docker images

docker.istio-ca:        $(ISTIO_DOCKER)/istio_ca     $(ISTIO_DOCKER)/ca-certificates.tgz
docker.istio-ca-test:   $(ISTIO_DOCKER)/istio_ca.crt $(ISTIO_DOCKER)/istio_ca.key
docker.node-agent:      $(ISTIO_DOCKER)/node_agent
docker.node-agent-test: $(ISTIO_DOCKER)/node_agent $(ISTIO_DOCKER)/istio_ca.key \
                        $(ISTIO_DOCKER)/node_agent.crt $(ISTIO_DOCKER)/node_agent.key
$(foreach FILE,$(NODE_AGENT_TEST_FILES),$(eval docker.node-agent-test: $(ISTIO_DOCKER)/$(notdir $(FILE))))

SECURITY_DOCKER:=docker.istio-ca docker.istio-ca-test docker.node-agent docker.node-agent-test
$(SECURITY_DOCKER): security/docker/Dockerfile$$(suffix $$@) | $(ISTIO_DOCKER)
	$(DOCKER_SPECIFIC_RULE)

# grafana image

$(foreach FILE,$(GRAFANA_FILES),$(eval docker.grafana: $(ISTIO_DOCKER)/$(notdir $(FILE))))
# Note that Dockerfile is too generic for parallel builds
docker.grafana: mixer/deploy/kube/conf/Dockerfile $(GRAFANA_FILES)
	$(DOCKER_GENERIC_RULE)

DOCKER_TARGETS:=$(PILOT_DOCKER) $(SERVICEGRAPH_DOCKER) $(MIXER_DOCKER) $(SECURITY_DOCKER) docker.grafana

# Rule used above for targets that use a Dockerfile name in the form Dockerfile.suffix
DOCKER_SPECIFIC_RULE=time (cp $< $(ISTIO_DOCKER)/ && cd $(ISTIO_DOCKER) && \
                     docker build -t $(subst docker.,,$@) -f Dockerfile$(suffix $@) .)

# Rule used above for targets that use the name Dockerfile or Dockerfile.debug .
# Note that these names overlap and thus aren't suitable for parallel builds.
# This is also why Dockerfiles are always copied (to avoid using another image's file).
DOCKER_GENERIC_RULE=time (cp $< $(ISTIO_DOCKER)/ && cd $(ISTIO_DOCKER) && \
                     docker build -t $(subst docker.,,$@) -f Dockerfile$(if $(findstring debug,$@),.debug) .)

docker.all: $(DOCKER_TARGETS)

# for each docker.XXX target create a tar.docker.XXX target that says how
# to make a $(ISTIO_OUT)/docker/XXX.tar.gz from the docker XXX image
# note that $(subst docker.,,$(TGT)) strips off the "docker." prefix, leaving just the XXX
$(foreach TGT,$(DOCKER_TARGETS),$(eval tar.$(TGT): $(TGT) | $(ISTIO_DOCKER_TAR) ; \
   time (docker save -o ${ISTIO_DOCKER_TAR}/$(subst docker.,,$(TGT)).tar $(subst docker.,,$(TGT)) && \
         gzip ${ISTIO_DOCKER_TAR}/$(subst docker.,,$(TGT)).tar)))

# create a DOCKER_TAR_TARGETS that's each of DOCKER_TARGETS with a tar. prefix
DOCKER_TAR_TARGETS:=
$(foreach TGT,$(DOCKER_TARGETS),$(eval DOCKER_TAR_TARGETS+=tar.$(TGT)))

# this target saves a tar.gz of each docker image to ${ISTIO_OUT}/docker/
docker.save: $(DOCKER_TAR_TARGETS)

# for each docker.XXX target create a tag.docker.XXX target that
# places another tag on the local docker image
$(foreach TGT,$(DOCKER_TARGETS),$(eval tag.$(TGT): | $(TGT) ; \
        docker tag $(subst docker.,,$(TGT)) $(HUB)/$(subst docker.,,$(TGT)):$(TAG)))

# create a DOCKER_TAG_TARGETS that's each of DOCKER_TARGETS with a tag. prefix
DOCKER_TAG_TARGETS:=
$(foreach TGT,$(DOCKER_TARGETS),$(eval DOCKER_TAG_TARGETS+=tag.$(TGT)))

# if first part of URL (i.e., hostname) is gcr.io then use gcloud for push
$(if $(findstring gcr.io,$(firstword $(subst /, ,$(HUB)))),\
        $(eval DOCKER_PUSH_CMD:=gcloud docker -- push),$(eval DOCKER_PUSH_CMD:=docker push))

# potentailly insert this before docker tag: $(DOCKER_SETUP) &&
#ifeq (${TEST_ENV},minikube)
#DOCKER_SETUP:=eval $$(minikube docker-env)
#else
## find a better way to insert a dummy command
#DOCKER_SETUP:=echo
#endif

# for each docker.XXX target create a push.docker.XXX target that pushes
# the local docker image to another hub
# a possible optimization is to use tag.$(TGT) as a dependency to do the tag for us
$(foreach TGT,$(DOCKER_TARGETS),$(eval push.$(TGT): | $(TGT) ; \
        time (docker tag $(subst docker.,,$(TGT)) $(HUB)/$(subst docker.,,$(TGT)):$(TAG) && \
                    $(DOCKER_PUSH_CMD) $(HUB)/$(subst docker.,,$(TGT)):$(TAG))))

# create a DOCKER_PUSH_TARGETS that's each of DOCKER_TARGETS with a push. prefix
DOCKER_PUSH_TARGETS:=
$(foreach TGT,$(DOCKER_TARGETS),$(eval DOCKER_PUSH_TARGETS+=push.$(TGT)))

# This target pushes each docker image to specified HUB and TAG.
# The push scripts support a comma-separated list of HUB(s) and TAG(s),
# but I'm not sure this is worth the added complexity to support.

# XXX consider whether to support:
# if [[ "${TEST_ENV}" == "minikube" ]]; then
#    eval $(minikube docker-env)
# fi

#ifeq (${TEST_ENV},minikube)
#docker.minikube:
#	eval $(minikube docker-env)
#docker.push: docker.minikube $(DOCKER_PUSH_TARGETS)
#else
docker.tag: $(DOCKER_TAG_TARGETS)
docker.push: $(DOCKER_PUSH_TARGETS)
#endif

# if first part of URL (i.e., hostname) is gcr.io then upload istioctl
$(if $(findstring gcr.io,$(firstword $(subst /, ,$(HUB)))),$(eval push: gcs.push.istioctl-all),)

push: docker.push installgen

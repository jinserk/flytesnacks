.SILENT:

# This is used by the image building script referenced below. Normally it just takes the directory name but in this
# case we want it to be called something else.
IMAGE_NAME=flytecookbook
export VERSION ?= $(shell git rev-parse HEAD)

define PIP_COMPILE
pip-compile $(1) ${PIP_ARGS} --upgrade --verbose
endef

# Set SANDBOX=1 to automatically fill in sandbox config
ifdef SANDBOX

# The url for Flyte Control plane
export FLYTE_HOST ?= localhost:30081

# Overrides s3 url. This is solely needed for SANDBOX deployments. Shouldn't be overriden in production AWS S3.
export FLYTE_AWS_ENDPOINT ?= http://localhost:30084/

# Used to authenticate to s3. For a production AWS S3, it's discouraged to use keys and key ids.
export FLYTE_AWS_ACCESS_KEY_ID ?= minio

# Used to authenticate to s3. For a production AWS S3, it's discouraged to use keys and key ids.
export FLYTE_AWS_SECRET_ACCESS_KEY ?= miniostorage

# Used to publish artifacts for fast registration
export ADDL_DISTRIBUTION_DIR ?= s3://flyte/fast/

# The base of where Blobs, Schemas and other offloaded types are, by default, serialized.
export OUTPUT_DATA_PREFIX ?= s3://flyte/raw-data

# Instructs flyte-cli commands to use insecure channel when communicating with Flyte's control plane.
# If you're port-forwarding your service or running the sandbox Flyte deployment, specify INSECURE=1 before your make command.
# If your Flyte Admin is behind SSL, don't specify anything.
ifndef INSECURE
	export INSECURE_FLAG=-i
endif

# The docker registry that should be used to push images.
# e.g.:
# export REGISTRY ?= ghcr.io/flyteorg
endif

# The Flyte project that we want to register under
export PROJECT ?= flytesnacks

# If the REGISTRY environment variable has been set, that means the image name will not just be tagged as
#   flytecookbook:<sha> but rather,
#   ghcr.io/flyteorg/flytecookbook:<sha> or whatever your REGISTRY is.
ifdef REGISTRY
	FULL_IMAGE_NAME = ${REGISTRY}/${IMAGE_NAME}
endif
ifndef REGISTRY
	FULL_IMAGE_NAME = ${IMAGE_NAME}
endif

# If you are using a different service account on your k8s cluster, add SERVICE_ACCOUNT=my_account before your make command
ifndef SERVICE_ACCOUNT
	SERVICE_ACCOUNT=default
endif

requirements.txt: export CUSTOM_COMPILE_COMMAND := $(MAKE) requirements.txt
requirements.txt: requirements.in install-piptools
	$(call PIP_COMPILE,requirements.in)

.PHONY: requirements
requirements: requirements.txt

.PHONY: fast_serialize
fast_serialize: clean _pb_output
	echo ${CURDIR}
	docker run -it --rm \
		-e FLYTE_CREDENTIALS_CLIENT_ID=${FLYTE_CREDENTIALS_CLIENT_ID} \
		-e FLYTE_CREDENTIALS_CLIENT_SECRET=${FLYTE_CREDENTIALS_CLIENT_SECRET} \
		-e FLYTE_CREDENTIALS_AUTH_MODE=basic \
		-e REGISTRY=${REGISTRY} \
		-e MAKEFLAGS=${MAKEFLAGS} \
		-e FLYTE_HOST=${FLYTE_HOST} \
		-e INSECURE_FLAG=${INSECURE_FLAG} \
		-e PROJECT=${PROJECT} \
		-e FLYTE_AWS_ENDPOINT=${FLYTE_AWS_ENDPOINT} \
		-e FLYTE_AWS_ACCESS_KEY_ID=${FLYTE_AWS_ACCESS_KEY_ID} \
		-e FLYTE_AWS_SECRET_ACCESS_KEY=${FLYTE_AWS_SECRET_ACCESS_KEY} \
		-e OUTPUT_DATA_PREFIX=${OUTPUT_DATA_PREFIX} \
		-e ADDL_DISTRIBUTION_DIR=${ADDL_DISTRIBUTION_DIR} \
		-e SERVICE_ACCOUNT=$(SERVICE_ACCOUNT) \
		-e VERSION=${VERSION} \
		-v ${CURDIR}/_pb_output:/tmp/output \
		-v ${CURDIR}:/root/$(shell basename $(CURDIR)) \
		${TAGGED_IMAGE} make fast_serialize

.PHONY: fast_register
fast_register: clean _pb_output ## Packages code and registers without building docker images.
	@echo "Tagged Image: "
	@echo ${TAGGED_IMAGE}
	@echo ${CURDIR}
	flyte-cli fast-register-files -h ${FLYTE_HOST} ${INSECURE_FLAG} -p ${PROJECT} -d development --kubernetes-service-account ${SERVICE_ACCOUNT} --output-location-prefix ${OUTPUT_DATA_PREFIX} --additional-distribution-dir ${ADDL_DISTRIBUTION_DIR} ${CURDIR}/_pb_output/*

.PHONY: docker_build
docker_build:
	echo "Tagged Image: "
	echo ${TAGGED_IMAGE}
	docker build ../ --build-arg tag="${TAGGED_IMAGE}" -t "${TAGGED_IMAGE}" -f Dockerfile

.PHONY: serialize
serialize: clean _pb_output docker_build
	@echo ${VERSION}
	@echo ${CURDIR}
	docker run -i --rm \
		-e FLYTE_CREDENTIALS_CLIENT_ID=${FLYTE_CREDENTIALS_CLIENT_ID} \
		-e FLYTE_CREDENTIALS_CLIENT_SECRET=${FLYTE_CREDENTIALS_CLIENT_SECRET} \
		-e FLYTE_CREDENTIALS_AUTH_MODE=basic \
		-e FLYTE_CREDENTIALS_SCOPES=all \
		-e REGISTRY=${REGISTRY} \
		-e MAKEFLAGS=${MAKEFLAGS} \
		-e FLYTE_HOST=${FLYTE_HOST} \
		-e INSECURE_FLAG=${INSECURE_FLAG} \
		-e PROJECT=${PROJECT} \
		-e FLYTE_AWS_ENDPOINT=${FLYTE_AWS_ENDPOINT} \
		-e FLYTE_AWS_ACCESS_KEY_ID=${FLYTE_AWS_ACCESS_KEY_ID} \
		-e FLYTE_AWS_SECRET_ACCESS_KEY=${FLYTE_AWS_SECRET_ACCESS_KEY} \
		-e OUTPUT_DATA_PREFIX=${OUTPUT_DATA_PREFIX} \
		-e ADDL_DISTRIBUTION_DIR=${ADDL_DISTRIBUTION_DIR} \
		-e SERVICE_ACCOUNT=$(SERVICE_ACCOUNT) \
		-e VERSION=${VERSION} \
		-v ${CURDIR}/_pb_output:/tmp/output \
		${TAGGED_IMAGE} make serialize


.PHONY: register
register: clean _pb_output serialize docker_push
	@echo ${VERSION}
	@echo ${CURDIR}
	flyte-cli register-files -h ${FLYTE_HOST} ${INSECURE_FLAG} -p ${PROJECT} -d development -v ${VERSION} --kubernetes-service-account ${SERVICE_ACCOUNT} --output-location-prefix ${OUTPUT_DATA_PREFIX} ${CURDIR}/_pb_output/*

_pb_output:
	mkdir -p _pb_output

.PHONY: clean
clean:
	rm -rf _pb_output/*

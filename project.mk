#-*- mode: gnumakefile; -*-

AWS_REGION ?= 'us-east-1'

TAG := test-amazon-credentials

.PHONY: image
image: test-container.pl $(TARBALL)
	@test -n "$(AWS_PROFILE)" || ( echo >&2 "set AWS_PROFILE" && exit 1;); \
	if [[ -z "$(AWS_ACCOUNT)" ]]; then \
	  account=$$(aws sts get-caller-identity --query Account --profile $(AWS_PROFILE) --output text); \
	else \
	  account="$(AWS_ACCOUNT)"; \
	fi; \
	logfile=$$(mktemp); trap 'rm -f $$logfile' EXIT; \
	docker build . -f Dockerfile -t $(TAG) 2>&1 | tee $$logfile; \
	cp $$logfile build.log

.PHONEY: deploy
deploy:
	@test -n "$(AWS_PROFILE)" || ( echo >&2 "set AWS_PROFILE" && exit 1;); \
	if [[ -z "$(AWS_ACCOUNT)" ]]; then \
	  account=$$(aws sts get-caller-identity --query Account --profile $(AWS_PROFILE) --output text); \
	else \
	  account="$(AWS_ACCOUNT)"; \
	fi; \
	repo-$$account.dkr.ecr.$(AWS_REGION).amazonaws.com; \
        docker tag $(TAG):latest $$repo/$(TAG):latest; \
        AWS_PROFILE=$(AWS_PROFILE) aws ecr get-login-password --region $(AWS_REGION) | \
           docker login --username AWS --password-stdin $$repo/$(TAG); \
	logfile=$$(mktemp); trap 'rm -f $$logfile' EXIT; \
        AWS_PROFILE=$(AWS_PROFILE) docker push $$repo/$(TAG):latest 2>&1 | tee $$logfile; \
	perl -ne 'chomp; ($$sha) = $$_ =~/digest: (sha256:[^ ]+)/; print $$sha;' $$logfile >image-digest

.PHONY: install
install: $(TARBALL)
	cpanm -n -v -l $(HOME) $<

# Interesting flags
# NAME=<test name> (example: cmd_async)

.PHONY: test demo

REPO_ROOT=$(realpath ./.)

ARGS += -vet
ARGS += -vet-packages:subprocess
ARGS += -disallow-do
ARGS += -warnings-as-errors
ARGS += -use-separate-modules
ifdef NAME
	ARGS += -define:ODIN_TEST_NAMES=tests.$(NAME)
endif

test:
	odin test tests $(ARGS) -define:REPO_ROOT=$(REPO_ROOT)

demo:
	make -B -C $(REPO_ROOT)/demos run

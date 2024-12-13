# Interesting flags
# NAME=<test name> (example: cmd_async)
# TARGET=<target> (example: windows_amd64, linux_amd64)
# ODIN=<odin executable>

ifeq ($(OS),Windows_NT)
	IS_WINDOWS = 1
endif
ifneq ($(filter windows_%, $(TARGET)),)
	IS_WINDOWS = 1
endif

.PHONY: test demo

REPO_ROOT := $(realpath ./.)

ODIN ?= odin

ARGS += -vet
ARGS += -vet-packages:subprocess
ARGS += -disallow-do
ARGS += -warnings-as-errors
ARGS += -use-separate-modules
ifdef TARGET
	ARGS += -target:$(TARGET)
endif
ifdef NAME
	ARGS += -define:ODIN_TEST_NAMES=tests.$(NAME)
endif

ifdef TARGET
	DEMO_ARGS += TARGET=$(TARGET)
endif
ifdef NAME
	DEMO_ARGS += NAME=$(NAME)
endif

test:
	$(ODIN) test tests $(ARGS) -define:REPO_ROOT="$(REPO_ROOT)"

demo:
	make -B -C "$(REPO_ROOT)/demos" run $(DEMO_ARGS)

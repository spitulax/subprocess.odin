# Interesting flags
# NAME=<demo name> (example: hello.odin)
# DEBUG=0, DEBUG=1
# TARGET=<target> (example: windows_amd64, linux_amd64)
# ODIN=<odin executable>

ifeq ($(OS),Windows_NT)
	IS_WINDOWS = 1
endif
ifneq ($(filter windows_%, $(TARGET)),)
	IS_WINDOWS = 1
endif

ODIN ?= odin
BUILD_DIR := ./build

ifdef NAME
	SRCS := $(notdir $(NAME))
else
	SRCS := $(shell find -type f -name '*.odin')
	SRCS := $(SRCS:./%=%)
endif
TARGETS := $(SRCS:%.odin=%)
TARGETS_LOC := $(addprefix $(BUILD_DIR)/, $(TARGETS))

ARGS += -build-mode:exe
ARGS += -vet
ARGS += -disallow-do
ARGS += -warnings-as-errors
ARGS += -use-separate-modules
ifeq ($(DEBUG),1)
	ARGS += -debug
else
	ARGS += -o:speed
endif
ifdef TARGET
	ARGS += -target:$(TARGET)
endif

ifeq ($(IS_WINDOWS),1)
	TARGETS_LOC := $(addsuffix .exe, $(TARGETS_LOC))
endif

.PHONY: build run clean mkdir

build: mkdir $(TARGETS_LOC)

run: $(TARGETS_LOC)
	@$(foreach x, $^, \
		echo -en '\033[1;34m'; \
		echo '####################'; \
		echo '# Running $(x)...'; \
		echo '####################'; \
		echo -en '\033[0m'; \
		./$(x); \
		echo;\
	)

ifeq ($(IS_WINDOWS),1)
$(TARGETS_LOC): $(BUILD_DIR)/%.exe: %.odin
else
$(TARGETS_LOC): $(BUILD_DIR)/%: %.odin
endif
	$(ODIN) build $< -file $(ARGS) -out:$@

clean: 
	rm -r $(BUILD_DIR)/*

mkdir:
ifeq ($(wildcard $(BUILD_DIR)/.),)
	mkdir -p $(BUILD_DIR)
endif

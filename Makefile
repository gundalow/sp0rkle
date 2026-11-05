NASM ?= nasm
CC ?= cc
BUILD_DIR := build
SOURCES := src/main.asm src/runtime/strings.asm src/runtime/logging.asm src/irc/protocol.asm
OBJECTS := $(patsubst src/%.asm,$(BUILD_DIR)/%.o,$(SOURCES))
TARGET := $(BUILD_DIR)/sp0rkle

.PHONY: all clean test
all: $(TARGET)

$(TARGET): $(OBJECTS)
	$(CC) -no-pie -o $@ $^

$(BUILD_DIR)/%.o: src/%.asm
	@mkdir -p $(dir $@)
	$(NASM) -f elf64 -g -F dwarf -Wall -Werror -w-no-reloc-rel-dword -o $@ $<

test: $(TARGET)
	./$(TARGET) --self-test
	sh ./tests/smoke.sh ./$(TARGET)

clean:
	rm -rf $(BUILD_DIR)

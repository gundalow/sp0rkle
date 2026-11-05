NASM ?= nasm
CC ?= cc
BUILD_DIR := build
SOURCES := src/main.asm src/runtime/strings.asm src/runtime/memory.asm src/runtime/logging.asm src/irc/protocol.asm src/irc/transport.asm src/bot/commands.asm src/bot/context.asm
OBJECTS := $(patsubst src/%.asm,$(BUILD_DIR)/%.o,$(SOURCES))
TARGET := $(BUILD_DIR)/sp0rkle
TRANSPORT_TEST := $(BUILD_DIR)/transport_test
COMMAND_TEST := $(BUILD_DIR)/command_test
CONTEXT_TEST := $(BUILD_DIR)/context_test
TRANSPORT_TEST_OBJECTS := $(BUILD_DIR)/runtime/strings.o $(BUILD_DIR)/runtime/memory.o $(BUILD_DIR)/irc/protocol.o $(BUILD_DIR)/irc/transport.o

.PHONY: all clean test
all: $(TARGET)

$(TARGET): $(OBJECTS)
	$(CC) -no-pie -o $@ $^

$(BUILD_DIR)/%.o: src/%.asm
	@mkdir -p $(dir $@)
	$(NASM) -f elf64 -g -F dwarf -Wall -Werror -w-reloc-rel-dword -o $@ $<

$(TRANSPORT_TEST): tests/transport_test.c $(TRANSPORT_TEST_OBJECTS)
	$(CC) -no-pie -o $@ $^

$(COMMAND_TEST): tests/command_test.c $(BUILD_DIR)/bot/commands.o
	$(CC) -no-pie -o $@ $^

$(CONTEXT_TEST): tests/context_test.c $(BUILD_DIR)/bot/context.o
	$(CC) -no-pie -o $@ $^

test: $(TARGET) $(TRANSPORT_TEST) $(COMMAND_TEST) $(CONTEXT_TEST)
	./$(TARGET) --self-test
	./$(TRANSPORT_TEST)
	./$(COMMAND_TEST)
	./$(CONTEXT_TEST)
	sh ./tests/smoke.sh ./$(TARGET)

clean:
	rm -rf $(BUILD_DIR)

NASM ?= nasm
CC ?= cc
BUILD_DIR := build
SOURCES := src/main.asm src/runtime/strings.asm src/runtime/memory.asm src/runtime/logging.asm src/irc/protocol.asm src/irc/events.asm src/irc/transport.asm src/bot/commands.asm src/bot/context.asm src/bot/context_emit.asm src/bot/filters.asm src/bot/rewrite.asm
OBJECTS := $(patsubst src/%.asm,$(BUILD_DIR)/%.o,$(SOURCES))
TARGET := $(BUILD_DIR)/sp0rkle
TRANSPORT_TEST := $(BUILD_DIR)/transport_test
COMMAND_TEST := $(BUILD_DIR)/command_test
CONTEXT_TEST := $(BUILD_DIR)/context_test
FILTER_TEST := $(BUILD_DIR)/filter_test
REWRITE_TEST := $(BUILD_DIR)/rewrite_test
CONTEXT_EMIT_TEST := $(BUILD_DIR)/context_emit_test
EVENT_TEST := $(BUILD_DIR)/event_test
TRANSPORT_TEST_OBJECTS := $(BUILD_DIR)/runtime/strings.o $(BUILD_DIR)/runtime/memory.o $(BUILD_DIR)/irc/protocol.o $(BUILD_DIR)/irc/transport.o

.PHONY: all clean test
all: $(TARGET)

$(TARGET): $(OBJECTS)
	$(CC) -no-pie -o $@ $^

$(BUILD_DIR)/%.o: src/%.asm
	@mkdir -p $(dir $@)
	$(NASM) -f elf64 -g -F dwarf -Wall -Werror -w-reloc-rel-dword -o $@ $<

$(EVENT_TEST): tests/event_test.c $(BUILD_DIR)/irc/events.o $(BUILD_DIR)/runtime/strings.o
	$(CC) -no-pie -o $@ $^

$(TRANSPORT_TEST): tests/transport_test.c $(TRANSPORT_TEST_OBJECTS)
	$(CC) -no-pie -o $@ $^

$(COMMAND_TEST): tests/command_test.c $(BUILD_DIR)/bot/commands.o $(BUILD_DIR)/bot/filters.o
	$(CC) -no-pie -o $@ $^

$(CONTEXT_TEST): tests/context_test.c $(BUILD_DIR)/bot/context.o
	$(CC) -no-pie -o $@ $^

$(FILTER_TEST): tests/filter_test.c $(BUILD_DIR)/bot/filters.o
	$(CC) -no-pie -o $@ $^

$(CONTEXT_EMIT_TEST): tests/context_emit_test.c $(BUILD_DIR)/bot/context_emit.o $(BUILD_DIR)/bot/rewrite.o
	$(CC) -no-pie -o $@ $^

$(REWRITE_TEST): tests/rewrite_test.c $(BUILD_DIR)/bot/rewrite.o
	$(CC) -no-pie -o $@ $^

test: $(TARGET) $(EVENT_TEST) $(TRANSPORT_TEST) $(COMMAND_TEST) $(CONTEXT_TEST) $(FILTER_TEST) $(REWRITE_TEST) $(CONTEXT_EMIT_TEST)
	./$(TARGET) --self-test
	./$(EVENT_TEST)
	./$(TRANSPORT_TEST)
	./$(COMMAND_TEST)
	./$(CONTEXT_TEST)
	./$(FILTER_TEST)
	./$(REWRITE_TEST)
	./$(CONTEXT_EMIT_TEST)
	sh ./tests/smoke.sh ./$(TARGET)

clean:
	rm -rf $(BUILD_DIR)

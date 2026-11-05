NASM ?= nasm
CC ?= cc
BUILD_DIR := build
SOURCES := src/main.asm src/runtime/strings.asm src/runtime/memory.asm src/runtime/logging.asm src/irc/protocol.asm src/irc/events.asm src/irc/transport.asm src/irc/serialize.asm src/bot/commands.asm src/bot/context.asm src/bot/irc_context.asm src/bot/irc_command.asm src/bot/irc_execute.asm src/bot/pollers.asm src/db/key.asm src/features/karma.asm src/features/karma_record.asm src/features/karma_apply.asm src/bot/context_emit.asm src/bot/filters.asm src/bot/rewrite.asm
OBJECTS := $(patsubst src/%.asm,$(BUILD_DIR)/%.o,$(SOURCES))
TARGET := $(BUILD_DIR)/sp0rkle
TRANSPORT_TEST := $(BUILD_DIR)/transport_test
COMMAND_TEST := $(BUILD_DIR)/command_test
CONTEXT_TEST := $(BUILD_DIR)/context_test
FILTER_TEST := $(BUILD_DIR)/filter_test
REWRITE_TEST := $(BUILD_DIR)/rewrite_test
CONTEXT_EMIT_TEST := $(BUILD_DIR)/context_emit_test
IRC_CONTEXT_TEST := $(BUILD_DIR)/irc_context_test
IRC_COMMAND_TEST := $(BUILD_DIR)/irc_command_test
POLLER_TEST := $(BUILD_DIR)/poller_test
DB_KEY_TEST := $(BUILD_DIR)/db_key_test
KARMA_TEST := $(BUILD_DIR)/karma_test
KARMA_RECORD_TEST := $(BUILD_DIR)/karma_record_test
KARMA_APPLY_TEST := $(BUILD_DIR)/karma_apply_test
EVENT_TEST := $(BUILD_DIR)/event_test
IRC_SERIALIZE_TEST := $(BUILD_DIR)/irc_serialize_test
TRANSPORT_TEST_OBJECTS := $(BUILD_DIR)/runtime/strings.o $(BUILD_DIR)/runtime/memory.o $(BUILD_DIR)/irc/protocol.o $(BUILD_DIR)/irc/transport.o

.PHONY: all clean test
all: $(TARGET)

$(TARGET): $(OBJECTS)
	$(CC) -no-pie -o $@ $^

$(BUILD_DIR)/%.o: src/%.asm
	@mkdir -p $(dir $@)
	$(NASM) -f elf64 -g -F dwarf -Wall -Werror -w-reloc-rel-dword -o $@ $<

$(IRC_SERIALIZE_TEST): tests/irc_serialize_test.c $(BUILD_DIR)/irc/serialize.o $(BUILD_DIR)/irc/transport.o $(BUILD_DIR)/irc/protocol.o $(BUILD_DIR)/runtime/strings.o $(BUILD_DIR)/runtime/memory.o
	$(CC) -no-pie -o $@ $^

$(EVENT_TEST): tests/event_test.c $(BUILD_DIR)/irc/events.o $(BUILD_DIR)/irc/transport.o $(BUILD_DIR)/irc/protocol.o $(BUILD_DIR)/runtime/strings.o $(BUILD_DIR)/runtime/memory.o
	$(CC) -no-pie -o $@ $^

$(IRC_COMMAND_TEST): tests/irc_command_test.c $(BUILD_DIR)/bot/irc_command.o $(BUILD_DIR)/bot/irc_execute.o $(BUILD_DIR)/bot/irc_context.o $(BUILD_DIR)/bot/context.o $(BUILD_DIR)/bot/context_emit.o $(BUILD_DIR)/bot/rewrite.o $(BUILD_DIR)/bot/commands.o $(BUILD_DIR)/bot/filters.o
	$(CC) -no-pie -o $@ $^

$(POLLER_TEST): tests/poller_test.c $(BUILD_DIR)/bot/pollers.o
	$(CC) -no-pie -o $@ $^

$(DB_KEY_TEST): tests/db_key_test.c $(BUILD_DIR)/db/key.o
	$(CC) -no-pie -o $@ $^

$(KARMA_TEST): tests/karma_test.c $(BUILD_DIR)/features/karma.o
	$(CC) -no-pie -o $@ $^

$(KARMA_RECORD_TEST): tests/karma_record_test.c $(BUILD_DIR)/features/karma_record.o
	$(CC) -no-pie -o $@ $^

$(KARMA_APPLY_TEST): tests/karma_apply_test.c $(BUILD_DIR)/features/karma_apply.o $(BUILD_DIR)/features/karma.o $(BUILD_DIR)/features/karma_record.o
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

$(IRC_CONTEXT_TEST): tests/irc_context_test.c $(BUILD_DIR)/bot/irc_context.o $(BUILD_DIR)/bot/context.o $(BUILD_DIR)/bot/context_emit.o $(BUILD_DIR)/bot/rewrite.o
	$(CC) -no-pie -o $@ $^

test: $(TARGET) $(IRC_CONTEXT_TEST) $(IRC_COMMAND_TEST) $(POLLER_TEST) $(DB_KEY_TEST) $(KARMA_TEST) $(KARMA_RECORD_TEST) $(KARMA_APPLY_TEST) $(IRC_SERIALIZE_TEST) $(EVENT_TEST) $(TRANSPORT_TEST) $(COMMAND_TEST) $(CONTEXT_TEST) $(FILTER_TEST) $(REWRITE_TEST) $(CONTEXT_EMIT_TEST)
	./$(TARGET) --self-test
	./$(IRC_CONTEXT_TEST)
	./$(IRC_COMMAND_TEST)
	./$(POLLER_TEST)
	./$(DB_KEY_TEST)
	./$(KARMA_TEST)
	./$(KARMA_RECORD_TEST)
	./$(KARMA_APPLY_TEST)
	./$(IRC_SERIALIZE_TEST)
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

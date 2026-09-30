PRIV_DIR = $(MIX_APP_PATH)/priv

ifeq ($(OS),Windows_NT)
NIF_EXT = .dll
LDFLAGS = -shared
else
NIF_EXT = .so
ifeq ($(shell uname -s),Darwin)
LDFLAGS = -dynamiclib -undefined dynamic_lookup
else
LDFLAGS = -shared
endif
endif

NIF = $(PRIV_DIR)/term_ui_tty_nif$(NIF_EXT)
SRC = c_src/term_ui_tty_nif.c

CFLAGS += -O2 -Wall -Wextra -fPIC -I"$(ERTS_INCLUDE_DIR)"

.PHONY: all clean

all: $(NIF)

$(PRIV_DIR):
	test ! -L $@ || test -e $@ || rm -f $@
	mkdir -p $@

$(NIF): $(SRC) | $(PRIV_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

clean:
	rm -f $(NIF)

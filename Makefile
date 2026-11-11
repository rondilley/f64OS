SRCDIR	:= $(shell pwd)
S_EXT	:= nasm
S_EXT2  := f
SOURCES_NASM := $(shell find $(SRCDIR) -name "*.$(S_EXT)")
SOURCES_FS := $(shell find $(SRCDIR) -name "*.$(S_EXT2)")
.PHONY: clean doom
all: doom os.bin

# DOOM is optional: if doom.bin does not build, os.bin is still made.
doom:
	-$(MAKE) -C doom

os.bin: $(SOURCES_ASM) $(SOURCES_NASM) $(SOURCES_FS) $(wildcard disk_files/doom/doom.bin) Makefile
	-./bootfile_extract.py
	./strip_forth_comments.py > kernel/f64_stripped.f
	nasm -fbin os.nasm -o os.bin
	./bootfile_extend.py

clean:
	rm -f *.bin
	-$(MAKE) -C doom clean

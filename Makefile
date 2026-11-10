SRCDIR	:= $(shell pwd)
S_EXT	:= nasm
S_EXT2  := f
SOURCES_NASM := $(shell find $(SRCDIR) -name "*.$(S_EXT)")
SOURCES_FS := $(shell find $(SRCDIR) -name "*.$(S_EXT2)")
.PHONY: clean
all: os.bin

os.bin: $(SOURCES_ASM) $(SOURCES_NASM) $(SOURCES_FS) Makefile
	./strip_forth_comments.py > kernel/f64_stripped.f
	nasm -fbin os.nasm -o os.bin
	./bootfile_extend.py

clean:
	rm *.bin

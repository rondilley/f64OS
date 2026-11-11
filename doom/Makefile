# Build DOOM (doomgeneric) as a flat binary for f64OS.
#
# Output: ../disk_files/doom/doom.bin, loaded by doom.f at DOOM_BASE.
# Needs: GNU make, gcc and GNU binutils (ld, objcopy) for x86-64.
#   Linux:   the native gcc (ELF output).
#   Windows: MSYS2 gcc (PE output). The flat binary is the same.

CC      ?= gcc
LD      ?= ld
OBJCOPY ?= objcopy

DOOM_BASE := 0x1000000

ifeq ($(origin CC),default)
  CC := gcc
endif

MACHINE := $(shell $(CC) -dumpmachine)
GCCINC  := $(shell $(CC) -print-file-name=include)
# An MSYS2 gcc prints a POSIX path. Convert it to a Windows path with the
# cygpath of the same MSYS2 tree, so that a shell from another MSYS runtime
# (for example Git Bash) does not change it.
CYGPATH := $(wildcard $(dir $(shell which $(CC) 2>/dev/null))cygpath*)
ifneq (,$(CYGPATH))
  GCCINC := $(shell "$(firstword $(CYGPATH))" -m "$(GCCINC)")
endif

CFLAGS := -O2 -std=gnu99 -ffreestanding -nostdinc -isystem $(GCCINC) \
          -If64/include -Idoomgeneric \
          -mno-red-zone -fno-pic -fno-pie -fno-stack-protector -fcommon \
          -fno-asynchronous-unwind-tables -fno-unwind-tables \
          -fno-strict-aliasing -fwrapv \
          -DF64OS -DFEATURE_SOUND -DCMAP256 -DDOOMGENERIC_RESX=320 -DDOOMGENERIC_RESY=200 \
          -Wall -Wno-unused -Wno-pointer-sign -Wno-format \
          -Wno-missing-braces -Wno-char-subscripts \
          -Werror=implicit-function-declaration

ifneq (,$(findstring msys,$(MACHINE))$(findstring cygwin,$(MACHINE))$(findstring mingw,$(MACHINE)))
  # PE toolchain: no stack probes, no host OS macros.
  CFLAGS  += -mno-stack-arg-probe -U__CYGWIN__ -U__MSYS__ -U_WIN32 -U_WIN64 -U__MINGW32__ -U__MINGW64__
  LDSCRIPT := f64/link-pe.ld
  LDFLAGS  := -m i386pep --image-base=0
else
  LDSCRIPT := f64/link-elf.ld
  LDFLAGS  := -m elf_x86_64 -z noexecstack --no-relax
endif

DOOM_SRC := dummy am_map doomdef doomstat dstrings d_event d_items d_iwad \
  d_loop d_main d_mode d_net f_finale f_wipe g_game hu_lib hu_stuff info \
  i_cdmus i_endoom i_joystick i_scale i_sound i_system i_timer memio m_argv \
  m_bbox m_cheat m_config m_controls m_fixed m_menu m_misc m_random p_ceilng \
  p_doors p_enemy p_floor p_inter p_lights p_map p_maputl p_mobj p_plats \
  p_pspr p_saveg p_setup p_sight p_spec p_switch p_telept p_tick p_user r_bsp \
  r_data r_draw r_main r_plane r_segs r_sky r_things sha1 sounds statdump \
  st_lib st_stuff s_sound tables v_video wi_stuff w_checksum w_file w_main \
  w_wad z_zone w_file_stdc i_input i_video doomgeneric mus2mid

OBJDIR := build
# f64_entry must be first: the loader jumps to the first byte of doom.bin.
OBJS := $(OBJDIR)/f64_entry.o $(OBJDIR)/doomgeneric_f64.o $(OBJDIR)/libc.o \
        $(OBJDIR)/sound_f64.o $(OBJDIR)/music_f64.o \
        $(addprefix $(OBJDIR)/,$(addsuffix .o,$(DOOM_SRC)))

OUT := ../disk_files/doom/doom.bin

.PHONY: all clean
all: $(OUT)

$(OUT): $(OBJDIR)/doom.exe
	$(OBJCOPY) -O binary $< $@
	@echo "doom.bin: $$(wc -c < $@) bytes"

$(OBJDIR)/doom.exe: $(OBJS) $(LDSCRIPT)
	$(LD) $(LDFLAGS) -T $(LDSCRIPT) -nostdlib -o $@ $(OBJS) -Map=$(OBJDIR)/doom.map

$(OBJDIR)/%.o: f64/%.c f64/include/f64.h Makefile | $(OBJDIR)
	@echo "  CC $<"
	@$(CC) $(CFLAGS) -c $< -o $@

$(OBJDIR)/%.o: doomgeneric/%.c Makefile | $(OBJDIR)
	@echo "  CC $<"
	@$(CC) $(CFLAGS) -c $< -o $@

$(OBJDIR):
	mkdir -p $(OBJDIR)

clean:
	rm -rf $(OBJDIR) $(OUT)

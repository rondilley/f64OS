# AUDIO selects the QEMU audio driver: pa, pipewire, alsa, sdl, or none.
# sb16 gives DOOM sound effects, adlib (OPL2) gives DOOM music.
make && qemu-system-x86_64 -m 128M -drive format=raw,file=os.bin \
    -audiodev ${AUDIO:-pa},id=snd0 \
    -device sb16,audiodev=snd0 -device adlib,audiodev=snd0

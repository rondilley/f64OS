# Windows equivalent of "make && ./run.sh".
# Needs: Python 3, NASM, QEMU (winget install NASM.NASM SoftwareFreedomConservancy.QEMU)
# Usage: .\run.ps1            build, then boot in QEMU
#        .\run.ps1 -BuildOnly build only
#        .\run.ps1 -NoDoom    do not build doom.bin
# DOOM:  also needs GNU make and an x86-64 gcc (MSYS2). If they are not on
#        PATH, the script skips doom.bin. See doom/README.md.
param([switch]$BuildOnly, [switch]$NoDoom)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Find-Tool($name, $candidates) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    throw "$name not found. Install it or add it to PATH."
}

$nasm = Find-Tool 'nasm' @(
    "$env:LOCALAPPDATA\bin\NASM\nasm.exe",
    "$env:ProgramFiles\NASM\nasm.exe")
$qemu = Find-Tool 'qemu-system-x86_64' @(
    "$env:ProgramFiles\qemu\qemu-system-x86_64.exe")
$python = Find-Tool 'python' @()

# The Forth sources must have LF line endings. A checkout with
# core.autocrlf=true gives CRLF, which breaks the comment stripper
# and puts CR bytes into the disk image.
$crlf = Get-ChildItem kernel\f64.f, disk_files -Recurse -File -Filter *.f |
    Where-Object { [IO.File]::ReadAllText($_.FullName).Contains("`r`n") }
if ($crlf) {
    throw ("CRLF line endings in: " + ($crlf.Name -join ', ') +
        "`nRun: git config core.autocrlf false, then convert the files to LF.")
}

# Build doom.bin into disk_files/doom before the disk image is made.
if (-not $NoDoom) {
    if ((Get-Command make -ErrorAction SilentlyContinue) -and
        (Get-Command gcc -ErrorAction SilentlyContinue)) {
        & make -C doom
        if ($LASTEXITCODE) { throw 'DOOM build failed' }
    } else {
        Write-Warning 'make or gcc not found: doom.bin not built.'
    }
}

# Copy DOOM savegames and config out of the old os.bin, so that the new
# image keeps them (see bootfile_extract.py).
& $python -I bootfile_extract.py
if ($LASTEXITCODE) { throw 'bootfile_extract.py failed' }

# Python on Windows writes CRLF to stdout, and a PowerShell redirect
# changes the encoding. Write the file from Python with LF endings.
& $python -I -c "import sys,runpy,io; b=io.StringIO(); o=sys.stdout; sys.stdout=b; runpy.run_path('strip_forth_comments.py'); sys.stdout=o; open('kernel/f64_stripped.f','w',newline='\n').write(b.getvalue())"
if ($LASTEXITCODE) { throw 'strip_forth_comments.py failed' }

& $nasm -fbin os.nasm -o os.bin
if ($LASTEXITCODE) { throw 'nasm failed' }

& $python -I bootfile_extend.py
if ($LASTEXITCODE) { throw 'bootfile_extend.py failed' }

if (-not $BuildOnly) {
    # 128 MiB: DOOM uses RAM up to 0x7000000 (see disk_files/doom/doom.f).
    # sb16 gives DOOM sound effects, adlib (OPL2) gives DOOM music.
    # -display sdl: on Windows, the default GTK window stops showing the
    # graphics mode while the sb16 DMA runs. The SDL window does not.
    & $qemu -m 128M -display sdl -drive format=raw,file=os.bin `
        -audiodev dsound,id=snd0 `
        -device sb16,audiodev=snd0 -device adlib,audiodev=snd0
}

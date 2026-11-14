# Valheim on arm64: a dedicated server on a Raspberry Pi 5, with mods and crossplay

Valheim's dedicated server is an x86-64 program. This is how to run it on a Raspberry Pi 5 under [Box64](https://github.com/ptitSeb/box64), with BepInEx mods and with crossplay, and the four things that stop it working if you don't know about them.

**The short version: check your memory page size first.** `getconf PAGESIZE` must say `4096`. A Pi 5 says `16384` out of the box, and on that the server crashes as soon as it gets busy. Section 1 is the one-line fix.

Worked out in November 2026 on Valheim 1.0.21, by [aronkleinhans](https://github.com/aronkleinhans) with Claude (Anthropic's AI model, in Claude Code) doing the heavy lifting: the setup, the crash hunt and the crossplay fix were worked out in one long session on the Pi itself. The start scripts are in [`scripts/`](scripts/), the Box64 change in [`box64-libogg-pageout_fill.patch`](box64-libogg-pageout_fill.patch).

## What you need to know first

Each of these fails silently or with a misleading error.

1. **Memory page size: use the 4K-page kernel.** Raspberry Pi OS runs the Pi 5 on a kernel with 16K memory pages; the game's runtime (Mono) expects the 4K pages of a PC. The server starts fine on 16K and then crashes under load (`Got a SIGSEGV while executing native code`), in our case every time a modded world got busy: eight runs, eight crashes. On the 4K kernel the same world ran without a single fault. It is not running out of memory, and no Box64 setting we tried fixed it.
2. **You don't need steamcmd or Box86.** steamcmd is 32-bit, which is why older guides have you set up Box86 first. [DepotDownloader](https://github.com/SteamRE/DepotDownloader) has a native arm64 build and fetches the server anonymously.
3. **BepInEx needs `BOX64_LD_PRELOAD`, not `LD_PRELOAD`.** BepInEx's own start script sets `LD_PRELOAD`, which tries to load its x86 injector into Box64 itself and never reaches the game. Nothing is logged; mods just don't load.
4. **Crossplay needs an audio codec.** The crossplay library (PlayFab Party) is a networking and voice chat library in one. It wants PulseAudio and libogg even on a headless server, doesn't declare libogg, and calls one libogg function that Box64's wrapper doesn't export yet. Without all three the server logs `DllNotFoundException: libParty.so` and carries on without crossplay.

## Tested on

- Raspberry Pi 5 Model B, 8 GB, official 27 W supply, active cooling
- Raspberry Pi OS Lite 64-bit (Debian 13 "trixie"), kernel `6.18.50+rpt-rpi-v8` (4K pages)
- Booting from a SATA SSD on USB 3 (an SD card works but is slow to load)
- Box64 0.4.5 built from git (`69642b9`, 2026-11-13)
- Valheim dedicated server 1.0.21, BepInExPack_Valheim 5.4.2351
- Mods on the server: Jotunn 2.30.2, Epic Loot 0.14.13, OreMines 1.2.1 and others

**What was and wasn't tested:** one player connected at a time, over Steam. Crossplay was taken as far as the server joining the PlayFab network and registering a join code; nobody joined by code. The numbers further down are from that setup. Treat "enough for a handful of friends" as an estimate.

**If you try it, say how it went.** Especially a join by crossplay code (console or Game Pass), which we had no device to test, and anything with several players on at once. [Open an issue](https://github.com/aronkleinhans/valheim-arm64/issues) with what worked or what broke.

## 1. Page size: the 4K kernel

Check what you have:

```bash
getconf PAGESIZE    # 16384 = the Pi 5's default 16K kernel, 4096 = what you need
```

If it says 16384, switch kernels:

```bash
echo "kernel=kernel8.img" | sudo tee -a /boot/firmware/config.txt
sudo reboot
```

After the reboot:

```bash
getconf PAGESIZE    # must print 4096
```

To go back, remove that line and reboot.

## 2. Packages

```bash
sudo apt update
sudo apt install -y git cmake build-essential python3 unzip curl tmux \
    libatomic1 libpulse0 libpulse-mainloop-glib0 libogg0
```

The last three are only for crossplay.

## 3. Box64

```bash
cd ~
git clone https://github.com/ptitSeb/box64
cd box64
```

For crossplay, enable the one libogg function the crossplay library needs. Box64 ships that line commented out (as of 2026-11-14); skip the step if yours already has it uncommented. `iFppi` is the function's shape (returns an int; takes two pointers and an int), the same as `ogg_stream_flush_fill` a few lines above it:

```bash
sed -i 's|^//GO(ogg_stream_pageout_fill,.*|GO(ogg_stream_pageout_fill, iFppi)|' src/wrapped/wrappedlibogg_private.h
```

Build and install (about ten minutes on a Pi 5):

```bash
mkdir build && cd build
cmake .. -DRPI5ARM64=1 -DCMAKE_BUILD_TYPE=RelWithDebInfo
make -j4
sudo make install
sudo systemctl restart systemd-binfmt
box64 --version
```

## 4. The server

```bash
mkdir -p ~/dd && cd ~/dd
curl -sLO https://github.com/SteamRE/DepotDownloader/releases/latest/download/DepotDownloader-linux-arm64.zip
unzip -o DepotDownloader-linux-arm64.zip && chmod +x DepotDownloader
./DepotDownloader -app 896660 -os linux -osarch 64 -dir ~/valheim-server
chmod +x ~/valheim-server/valheim_server.x86_64
```

About 2 GB. Run the same `DepotDownloader` line again to update the server after a game patch.

## 5. A vanilla server

Save as `~/valheim-server/run.sh` and `chmod +x` it. Change the name, world and password (at least five characters, and not part of the name).

```bash
#!/bin/bash
cd ~/valheim-server
export LD_LIBRARY_PATH=./linux64:$LD_LIBRARY_PATH
export SteamAppId=892970
exec box64 ./valheim_server.x86_64 -nographics -batchmode \
    -name "MyServer" -port 2456 -world "MyWorld" -password "changeme" -public 0 \
    -logFile ~/valheim-server/server.log
```

Run it in tmux so it survives your SSH session:

```bash
tmux new-session -d -s valheim ~/valheim-server/run.sh
tail -f ~/valheim-server/server.log     # wait for "Opened Steam server"
```

Stop it with `tmux attach -t valheim` and Ctrl-C; the server saves the world on the way out.

A new world takes a couple of minutes to generate the first time. Join from the game with the Pi's address and port 2456. From outside your home network you need UDP 2456–2457 forwarded, a VPN, or crossplay (below).

## 6. Mods (BepInEx)

Download [BepInExPack_Valheim](https://thunderstore.io/c/valheim/p/denikson/BepInExPack_Valheim/) and copy the contents of its inner `BepInExPack_Valheim` folder (`BepInEx/`, `doorstop_libs/`, `doorstop_config.ini`, …) into `~/valheim-server/`. Put plugin DLLs in `~/valheim-server/BepInEx/plugins/`.

Save as `~/valheim-server/run-bepinex.sh`:

```bash
#!/bin/bash
cd ~/valheim-server
export DOORSTOP_ENABLED=1
export DOORSTOP_TARGET_ASSEMBLY=./BepInEx/core/BepInEx.Preloader.dll
export LD_LIBRARY_PATH=./doorstop_libs:./linux64:$LD_LIBRARY_PATH
export BOX64_LD_LIBRARY_PATH=./doorstop_libs:./linux64
export BOX64_LD_PRELOAD=libdoorstop_x64.so
export SteamAppId=892970
exec box64 ./valheim_server.x86_64 -nographics -batchmode \
    -name "MyServer" -port 2456 -world "MyWorld" -password "changeme" -public 0 \
    -logFile ~/valheim-server/server.log
```

It worked if `~/valheim-server/BepInEx/LogOutput.log` ends its start-up with `Chainloader startup complete (N loaded, 0 skipped, 0 failed)`.

Things that caught us:

- **A plugin's dependencies must be on the server too.** `Could not load [X] because it has missing dependencies` in `LogOutput.log` names them (Epic Loot needs `NewtonsoftJsonDetector` beside `Newtonsoft.Json.dll`).
- **Clients are refused if the server lacks a mod they have** when that mod checks versions (anything registered through Jotunn, and mods using ServerSync). The refusal screen on the client lists what is missing.
- **Heavy mods make the start slower.** Epic Loot added about two minutes.

## 7. Crossplay

With the three packages and the Box64 line from above in place, add libogg to the preload and `-crossplay` to the arguments.

Vanilla: add this line to `run.sh` before `exec`:

```bash
export BOX64_LD_PRELOAD=libogg.so.0
```

Modded: change the preload line in `run-bepinex.sh` to:

```bash
export BOX64_LD_PRELOAD=libdoorstop_x64.so:libogg.so.0
```

and in either script end the server's arguments with `-crossplay`.

It worked if `server.log` shows `Joined PlayFab Party network` and `Session "…" registered with join code NNNNNN`. If it shows `DllNotFoundException: libParty.so`, one of the three pieces is missing; see Troubleshooting for how to find which.

With crossplay on, players join by code through the game's relay, so no port has to be opened on your router.

## What it costs to run

Measured on the setup above, one core being 100 %:

| | CPU | Memory |
| --- | --- | --- |
| Vanilla, nobody connected | about 21 % | 2.4 GB |
| Modded, nobody connected | 21–23 % | 3.1 GB |
| Modded, one player playing | 28–35 %, short spikes when new terrain generates | 3.2 GB |

55–63 °C with the official active cooler, never throttled. Time from launch to joinable: about 2 min 20 s vanilla, 4 min 30 s with Epic Loot.

In Valheim each player's PC simulates the creatures around that player and the server mostly relays, so the server's load grows slowly with players. Mods that do their own work on the server pay the emulation price: the one we measured ran about nine times slower than on a desktop Xeon.

## Troubleshooting

- **Mods don't load, nothing in the log:** you are using `LD_PRELOAD`. It has to be `BOX64_LD_PRELOAD`.
- **`… is not an executable file`:** `chmod +x valheim_server.x86_64`.
- **Crashes under load with `Got a SIGSEGV while executing native code`:** check `getconf PAGESIZE`. If it says 16384 you are on the 16K kernel.
- **A library won't load (`DllNotFoundException`, `Failed to open plugin`):** start once with `BOX64_LOG=1` in front of the script and search the output for the library's name. Box64 prints which needed library or which symbol it couldn't find. `BOX64_SHOWSEGV=1` prints details of a crash.
- **`Error initializing native libSDL3.so.0`** in the output is harmless on a headless server.
- **After a server update** `valheim_server.x86_64` may lose its executable bit again.

Two settings we used while chasing the 16K crashes, before finding the kernel was the cause. They made a marginal case survive there; we have not checked whether they do anything on the 4K kernel:

```bash
export GC_MARKERS=1 GC_NPROCS=1                      # in the run script
sed -i '/^gc-max-time-slice/d' valheim_server_Data/boot.config
```

## See also

Others are working on the same thing, and some of it overlaps with this guide:

- [Box64 issue #4403](https://github.com/ptitSeb/box64/issues/4403) (open, September 2026): on a Pi 4 with recent Box64, crossplay's join-code registration never completes. On the setup above it did complete (`registered with join code`); we don't know which difference matters.
- [zhmarvi/valheim-arm64](https://github.com/zhmarvi/valheim-arm64): a container and Kubernetes manifests, vanilla, also fetched with DepotDownloader.
- [benjamin-wiemann/valheim-server-docker-arm64](https://github.com/benjamin-wiemann/valheim-server-docker-arm64): a Docker image with BepInEx support.
- [husjon/valheim_server_oci_setup](https://github.com/husjon/valheim_server_oci_setup): Valheim on Oracle Cloud's ARM machines.

None of these mention the 16K page size, which is specific to the Pi 5's default kernel (a Pi 4 and most ARM servers already use 4K pages).

## Not covered

- Running it as a systemd service, automatic updates, off-machine backups.
- Other ARM boards. The kernel point is specific to systems with 16K pages; everything else should carry over.
- More than one player at a time, and a join by crossplay code: see "Tested on".

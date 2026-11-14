#!/bin/bash
# Modded (BepInEx) Valheim dedicated server under Box64. Change the name, world and password.
cd ~/valheim-server
export DOORSTOP_ENABLED=1
export DOORSTOP_TARGET_ASSEMBLY=./BepInEx/core/BepInEx.Preloader.dll
export LD_LIBRARY_PATH=./doorstop_libs:./linux64:$LD_LIBRARY_PATH
export BOX64_LD_LIBRARY_PATH=./doorstop_libs:./linux64
# BOX64_LD_PRELOAD, not LD_PRELOAD: plain LD_PRELOAD never reaches the emulated game.
# For crossplay: use the second line instead and add -crossplay to the arguments below.
export BOX64_LD_PRELOAD=libdoorstop_x64.so
#export BOX64_LD_PRELOAD=libdoorstop_x64.so:libogg.so.0
export SteamAppId=892970
exec box64 ./valheim_server.x86_64 -nographics -batchmode \
    -name "MyServer" -port 2456 -world "MyWorld" -password "changeme" -public 0 \
    -logFile ~/valheim-server/server.log

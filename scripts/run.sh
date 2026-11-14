#!/bin/bash
# Vanilla Valheim dedicated server under Box64. Change the name, world and password.
cd ~/valheim-server
export LD_LIBRARY_PATH=./linux64:$LD_LIBRARY_PATH
export SteamAppId=892970
# For crossplay: uncomment the next line and add -crossplay to the arguments below.
#export BOX64_LD_PRELOAD=libogg.so.0
exec box64 ./valheim_server.x86_64 -nographics -batchmode \
    -name "MyServer" -port 2456 -world "MyWorld" -password "changeme" -public 0 \
    -logFile ~/valheim-server/server.log

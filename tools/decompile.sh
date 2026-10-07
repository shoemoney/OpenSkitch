#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
JAVA_HOME="/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home"
export JAVA_HOME
mkdir -p "$ROOT/analysis/ghidra"
exec /opt/homebrew/opt/ghidra/libexec/support/analyzeHeadless "$ROOT/analysis/ghidra" SkitchRedux -import "$ROOT/original/Skitch.app/Contents/MacOS/Skitch" -overwrite -scriptPath "$ROOT/tools" -postScript ExportDecompiled.java "$ROOT/analysis/decompiled.c" -analysisTimeoutPerFile 300 -log "$ROOT/analysis/ghidra.log"

#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

command -v docker >/dev/null || { echo 'docker is required'; exit 2; }

# Generate the bcrypt password hash used by Caddy. The plaintext test credential is:
#   user = ffmpeg
#   pass = secret
AUTH_HASH=$(docker run --rm caddy:2 caddy hash-password --plaintext secret)
export AUTH_HASH

cleanup() {
  docker compose down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p bin
if [[ ! -f bin/ffmpeg.exe || ! -f bin/ffprobe.exe ]]; then
  echo 'Copy ffmpeg.exe and ffprobe.exe into ./bin first.' >&2
  exit 2
fi

echo '== building tester image =='
docker compose build tester

echo '== starting server =='
docker compose up -d server

echo '== running tests =='
docker compose run --rm tester

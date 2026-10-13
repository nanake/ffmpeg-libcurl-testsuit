#!/usr/bin/env bash
set -uo pipefail

HOST="${TEST_HOST:-test.local}"; HTTP_PORT="${HTTP_PORT:-8080}"; HTTPS_PORT="${HTTPS_PORT:-8443}"
BASE_HTTP="http://${HOST}:${HTTP_PORT}"; BASE_HTTPS="https://${HOST}:${HTTPS_PORT}"
BIN="${BIN:-/work/bin}"; FFPROBE="$BIN/ffprobe.exe"; FFMPEG="$BIN/ffmpeg.exe"
PASS=0; FAIL=0; SKIP=0

run() {
    env WINEDEBUG=-all XDG_RUNTIME_DIR=/tmp/wine-runtime wine "$@"
}

ok() {
    PASS=$((PASS+1))
    printf 'PASS %-54s\n' "$1"
}

bad() {
    FAIL=$((FAIL+1))
    printf 'FAIL %-54s\n' "$1"
}

skip() {
    SKIP=$((SKIP+1))
    printf 'SKIP %-54s\n' "$1"
}

err() {
    sed -n '1,14p' "$1" >&2
}

cleanup() {
    rm -rf /tmp/out /tmp/e* /tmp/md5-* /tmp/wine-runtime /tmp/server.wav
}

trap cleanup EXIT
mkdir -p /tmp/wine-runtime /tmp/out

[[ -f "$FFPROBE" && -f "$FFMPEG" ]] || { echo 'ffmpeg.exe/ffprobe.exe not found in /work/bin' >&2; exit 2; }
printf '\n=== FFmpeg/libcurl Docker test suite ===\n'
printf '\n--- libcurl protocol ---\n'

if run "$FFPROBE" -hide_banner -protocols 2>&1 | grep -Eq '(^|[[:space:]])libcurl([[:space:]]|$)'; then
    echo 'libcurl protocol: present'
else
    echo 'libcurl protocol: MISSING'
    exit 4;
fi

# Establish that the Caddy service itself is reachable from the tester.
if curl -fsS --max-time 5 "$BASE_HTTP/media/test.wav" -o /tmp/server.wav && [[ -s /tmp/server.wav ]]; then :
else
    echo 'server is not reachable from tester' >&2
    exit 3;
fi

cp /work/www/media/test.wav /tmp/local.wav

# 1 Explicit libcurl: actual FFmpeg demux/decode, not ffprobe's reported remote size.
if run "$FFMPEG" -hide_banner -loglevel error -i "libcurl:${BASE_HTTP}/media/test.wav" -map 0:a:0 -frames:a 1 -f null - >/dev/null 2>/tmp/e1; then
    ok 'explicit libcurl: HTTP GET'
else
    bad 'explicit libcurl: HTTP GET'
    err /tmp/e1;
fi

# 2 Payload integrity.
run "$FFMPEG" -hide_banner -loglevel error -i /tmp/local.wav -map 0:a:0 -f md5 /tmp/md5-local.txt >/dev/null 2>/tmp/e2
run "$FFMPEG" -hide_banner -loglevel error -i "libcurl:${BASE_HTTP}/media/test.wav" -map 0:a:0 -f md5 /tmp/md5-http.txt >/dev/null 2>/tmp/e3

if [[ -s /tmp/md5-local.txt && -s /tmp/md5-http.txt ]] && diff -q /tmp/md5-local.txt /tmp/md5-http.txt >/dev/null; then
    ok 'HTTP payload/media integrity'
else
    bad 'HTTP payload/media integrity'
    err /tmp/e3;
fi

# 3 Force ordinary HTTP protocol through libcurl.
if run "$FFMPEG" -hide_banner -loglevel error -prefer_libcurl 1 -i "$BASE_HTTP/media/test.wav" -map 0:a:0 -frames:a 1 -f null - >/dev/null 2>/tmp/e4; then
    ok 'prefer_libcurl=1 HTTP GET'
else
    bad 'prefer_libcurl=1 HTTP GET'
    err /tmp/e4;
fi

# 4 Redirect.
if run "$FFMPEG" -hide_banner -loglevel error -i "libcurl:${BASE_HTTP}/redirect" -map 0:a:0 -frames:a 1 -f null - >/dev/null 2>/tmp/e5; then
    ok 'HTTP redirect'
else
    bad 'HTTP redirect'
    err /tmp/e5
fi

# 5 Basic auth: compare decoded content to the protected fixture, not to public fixture.
run "$FFMPEG" -hide_banner -loglevel error -i /work/www/private/secret.wav -map 0:a:0 -f md5 /tmp/md5-secret-local.txt >/dev/null 2>/tmp/e6a
run "$FFMPEG" -hide_banner -loglevel error -i "libcurl:http://ffmpeg:secret@${HOST}:${HTTP_PORT}/private/secret.wav" -map 0:a:0 -f md5 /tmp/md5-secret-http.txt >/dev/null 2>/tmp/e6b

if [[ -s /tmp/md5-secret-local.txt && -s /tmp/md5-secret-http.txt ]] && diff -q /tmp/md5-secret-local.txt /tmp/md5-secret-http.txt >/dev/null; then
    ok 'HTTP Basic Authentication'
else
    bad 'HTTP Basic Authentication'
    err /tmp/e6b
fi

# 6 HTTPS with verification disabled.
if run "$FFMPEG" -hide_banner -loglevel error -tls_verify 0 -i "libcurl:${BASE_HTTPS}/media/test.wav" -map 0:a:0 -frames:a 1 -f null - >/dev/null 2>/tmp/e7; then
    ok 'HTTPS + OpenSSL (verify off)'
else
    bad 'HTTPS + OpenSSL (verify off)'
    err /tmp/e7
fi

# 7 Internal CA verification.
CA_FILE=/caddy-data/caddy/pki/authorities/local/root.crt

if [[ -f "$CA_FILE" ]]; then
    if run "$FFMPEG" -hide_banner -loglevel error -ca_file "Z:${CA_FILE}" -i "libcurl:${BASE_HTTPS}/media/test.wav" -map 0:a:0 -frames:a 1 -f null - >/dev/null 2>/tmp/e8; then
      ok 'HTTPS certificate verification with CA file'
    else
      bad 'HTTPS certificate verification with CA file'
      err /tmp/e8
    fi
else
    bad 'HTTPS certificate verification with CA file (CA missing)'
fi

# 8 Default verification must reject the private Caddy CA.
if run "$FFMPEG" -hide_banner -loglevel error -i "libcurl:${BASE_HTTPS}/media/test.wav" -map 0:a:0 -frames:a 1 -f null - >/dev/null 2>/tmp/e9; then
    bad 'HTTPS rejects unknown CA'
else
    ok 'HTTPS rejects unknown CA'
fi

# 9 Compression/content decoding.
run "$FFMPEG" -hide_banner -loglevel error -i "libcurl:${BASE_HTTP}/media/test.wav" -map 0:a:0 -f md5 /tmp/md5-encoded.txt >/dev/null 2>/tmp/e10

if [[ -s /tmp/md5-encoded.txt ]] && diff -q /tmp/md5-local.txt /tmp/md5-encoded.txt >/dev/null; then
    ok 'HTTP content decoding'
else
    bad 'HTTP content decoding'
    err /tmp/e10;
fi

# 10 HTTP/2: require successful request and libcurl debug negotiation to say HTTP/2.
run "$FFMPEG" -hide_banner -loglevel debug -tls_verify 0 -http_version 2 -i "libcurl:${BASE_HTTPS}/media/test.wav" -map 0:a:0 -frames:a 1 -f null - >/dev/null 2>/tmp/e11

if grep -Eqi 'HTTP/2|using HTTP/2' /tmp/e11; then
    ok 'HTTP/2 over TLS'
else
    bad 'HTTP/2 over TLS'
    err /tmp/e11
fi

# 11 HTTP/3. Treat known lack of QUIC support/runtime as SKIP; otherwise require success.
run "$FFMPEG" -hide_banner -loglevel debug -tls_verify 0 -http_version 3only -i "libcurl:${BASE_HTTPS}/media/test.wav" -map 0:a:0 -frames:a 1 -f null - >/dev/null 2>/tmp/e12

if grep -Eqi 'HTTP/3|using HTTP/3' /tmp/e12; then
    ok 'HTTP/3 over QUIC'
elif grep -Eqi 'not supported|unsupported|not built|CURLE_NOT_BUILT_IN|HTTP.?3.*not available|QUIC.*not available' /tmp/e12; then
    skip 'HTTP/3 over QUIC (runtime/libcurl unavailable)'
else
    bad 'HTTP/3 over QUIC'
    err /tmp/e12
fi

# 12 Seek/range path.
if run "$FFMPEG" -hide_banner -loglevel error -ss 1 -i "libcurl:${BASE_HTTP}/media/test.wav" -frames:a 1 -f null - >/dev/null 2>/tmp/e13; then
    ok 'HTTP ranged/seekable read'
else
    bad 'HTTP ranged/seekable read'
    err /tmp/e13
fi

printf '\n=== result: %d passed, %d failed, %d skipped ===\n' "$PASS" "$FAIL" "$SKIP"
[[ $FAIL -eq 0 ]]

# FFmpeg/libcurl Docker test suite

Self-contained HTTP/HTTPS test server for testing an FFmpeg Windows build with libcurl.

Place `ffmpeg.exe` and `ffprobe.exe` in `bin/`, then run `./run-tests.sh`.

Tests use actual FFmpeg decode/open operations rather than comparing `ffprobe format=size` for remote resources. HTTP/2 and HTTP/3 inspect verbose libcurl negotiation. HTTP/3 is SKIP only when the runtime/libcurl reports that QUIC/HTTP3 is unavailable.

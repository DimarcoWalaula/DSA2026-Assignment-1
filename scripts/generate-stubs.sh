#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Generates the Ballerina gRPC stub (rental_pb.bal) for the Question 2 server
# and client from proto/rental.proto.
#
# Run this once after cloning, before `bal run` in either Question 2 package.
#
#   ./scripts/generate-stubs.sh
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROTO="$ROOT/proto/rental.proto"

command -v bal >/dev/null 2>&1 || {
    echo "Ballerina ('bal') is not on the PATH. Install Swan Lake from https://ballerina.io/downloads/"
    exit 1
}

# Recent Swan Lake distributions ship the gRPC code generator as a separate
# Ballerina tool rather than a built-in subcommand, so it has to be pulled
# once before `bal grpc` works.
if ! bal grpc --help >/dev/null 2>&1; then
    echo "The 'grpc' Ballerina tool is not installed yet - pulling it now ..."
    bal tool pull grpc
fi

echo "Generating stub for the server ..."
bal grpc --input "$PROTO" --output "$ROOT/rental-accommodation-server"

echo "Generating stub for the client ..."
bal grpc --input "$PROTO" --output "$ROOT/rental-accommodation-client"

for f in "$ROOT/rental-accommodation-server/rental_pb.bal" "$ROOT/rental-accommodation-client/rental_pb.bal"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: expected stub was not created: $f"
        exit 1
    fi
done

echo
echo "Done. Both packages now contain rental_pb.bal:"
ls -1 "$ROOT/rental-accommodation-server/rental_pb.bal" "$ROOT/rental-accommodation-client/rental_pb.bal"

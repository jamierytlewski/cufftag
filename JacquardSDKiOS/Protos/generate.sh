#!/bin/sh
#
# Regenerates JacquardSDK/Protobuf/*.pb.swift from the .proto files in this
# directory. Requires protoc and a protoc-gen-swift matching the SwiftProtobuf
# version in Package.swift:
#
#   brew install protobuf swift-protobuf
#
# The upstream SDK shipped only the generated Swift; these .proto files were
# reconstructed from it and verified to regenerate an equivalent schema.

set -eu
cd "$(dirname "$0")"
OUT=../JacquardSDK/Protobuf

protoc --swift_out="$OUT" jacquard.proto
protoc --swift_opt=Visibility=Public --swift_out="$OUT" publicSdk.proto

# Hide protobuf plumbing from the jazzy docs.
perl -pi -e 's{^( *)(public (?:var unknownFields|init\(\) \{\}))}{$1/// :nodoc:\n$1$2}' \
  "$OUT/publicSdk.pb.swift"

#!/usr/bin/env bash
set -eu

NIXPKGS=${1-"<nixpkgs>"}
cat <<EOF
{
  doubles = $(nix-instantiate --eval --strict "$NIXPKGS" -A lib.systems.doubles);
  supported = $(nix-instantiate --eval --strict "$NIXPKGS" -A lib.systems.supported);
}
EOF

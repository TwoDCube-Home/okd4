#!/usr/bin/env bash

set -euxo pipefail

oc adm drain "$1" --force --ignore-daemonsets --delete-emptydir-data
oc debug "node/$1" -- chroot /host shutdown -r +1
sleep 180
oc adm uncordon "$1"
oc wait node "$1" --for=condition=Ready --timeout=1h

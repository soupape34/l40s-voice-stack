#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ffmpeg git python3-venv python3-pip tmux
mkdir -p /root/l40s-voice-stack
touch /var/log/voice-stack-userdata.done

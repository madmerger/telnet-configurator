#!/bin/sh
docker rm -f cbt-bs-sim-ssh >/dev/null 2>&1 && echo "lab/docker: stopped" || true

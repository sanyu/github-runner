# Self-hosted GitHub Actions runner image with a baked Nix + devbox toolchain.
#
# Extends the standard runner image so CI that runs its steps through
# `devbox run -- ...` works on a runner that ships no Nix (and no systemd) — without
# installing Nix on every job.
#
# The container has no systemd, so an installer that assumes an init system fails.
# This uses the Determinate Systems installer with `--init none` (no systemd unit);
# it also creates the `nixbld` build group itself, which the upstream single-user
# script does NOT do when run as root (it aborts with
# "the group 'nixbld' ... does not exist").
#
# Generic on purpose: bakes Nix + devbox only, not any project's packages. Each repo's
# CI runs `devbox run` against its OWN checked-out devbox.json. A repo that wants a
# pre-warmed store can layer its own image: FROM this + COPY devbox.* + RUN devbox install.
FROM myoung34/github-runner:2.336.0-ubuntu-noble

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Fetch/unpack tools the Nix installer + devbox need.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl xz-utils ca-certificates git sudo \
 && rm -rf /var/lib/apt/lists/*

# --- Nix, daemonless ---------------------------------------------------------
# --init none: no systemd unit (the container has none). Jobs run as root and root
# owns /nix, so nix operates on the store directly without a running daemon.
#
# filter-syscalls = false + sandbox = false: the runner container runs under a
# restricted seccomp profile without the caps Nix's syscall filter / build sandbox
# need, so Nix otherwise dies with "unable to load seccomp BPF program: Invalid
# argument". Disabling both is the standard container config and safe for CI use.
RUN curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix -o /tmp/nix-installer \
 && chmod +x /tmp/nix-installer \
 && /tmp/nix-installer install linux --init none --no-confirm \
 && rm -f /tmp/nix-installer \
 && printf 'extra-experimental-features = nix-command flakes\nfilter-syscalls = false\nsandbox = false\n' \
      >> /etc/nix/nix.conf

# Nix + devbox on PATH for the runner process AND every job step it spawns. GitHub
# `run:` steps use a NON-login bash that never sources /etc/profile.d, so this ENV
# (inherited by all child processes) is the load-bearing mechanism.
ENV PATH=/nix/var/nix/profiles/default/bin:/usr/local/bin:${PATH}

# --- devbox CLI ---
RUN curl -fsSL https://get.jetify.com/devbox | FORCE=1 bash \
 && devbox version

# The base image ENTRYPOINT/CMD (the runner agent) is inherited unchanged.
#
# CAVEAT: assumes jobs run as root (base image default) so /nix (root-owned) is usable
# without a daemon. For a non-root runner user, start nix-daemon in an entrypoint or
# install Nix for that user's HOME instead.

# github-runner

A self-hosted GitHub Actions runner image with a **Nix** + **devbox** toolchain baked in. It extends `myoung34/github-runner:2.336.0-ubuntu-noble` so that CI which runs its steps through `devbox run -- ...` works on a runner that ships no Nix — without installing Nix on every job.

## Why this exists

Runner containers often have **no systemd**. Installing Nix per CI run with an installer that assumes an init system fails on such a container:

```
Error: Planner error ... Could not detect systemd; you may be able to get up and
running without systemd with `nix-installer install linux --init none`.
```

Baking a daemonless Nix + devbox in at build time removes that per-run install step entirely (and the Actions nix-store cache it depends on, which needs `actions: write` on the job token).

## What's inside (generic on purpose)

- Base: `myoung34/github-runner:2.336.0-ubuntu-noble` (the GitHub Actions runner agent).
- Nix installed daemonless via the Determinate Systems installer (`--init none`); jobs run as root and root owns `/nix`, so nix operates on the store directly with no running daemon. `nix-command flakes` enabled.
- `devbox` CLI on `PATH`.

It bakes **no project's packages**. Each repo's CI runs `devbox run` against its **own** checked-out `devbox.json`, which resolves that repo's pinned toolchain at run time. One image, usable by any repo.

**Want a pre-warmed store for a specific repo?** Layer a thin image on top:

```dockerfile
FROM ghcr.io/<owner>/github-runner:2.336.0-noble
COPY devbox.json devbox.lock /opt/prewarm/
RUN cd /opt/prewarm && devbox install
```

Only worthwhile when a repo's toolchain download dominates CI time; an ephemeral runner starts fresh from the image each job, so a baked store is that repo's warm cache.

## Build + push

The runner target is `linux/amd64`.

### Primary: GitHub Actions — `.github/workflows/build.yml`

The image builds + pushes automatically on a GitHub-hosted `ubuntu-latest` runner whenever `Dockerfile` (or the workflow) changes on `main`, or on manual `workflow_dispatch`. It uses the built-in `GITHUB_TOKEN` (no PAT) to push to `ghcr.io/<owner>/github-runner:2.336.0-noble` + `:latest`. Native amd64 (no emulation), and only runs on Dockerfile/version changes.

Rebuild on demand: Actions tab → **build-image** → *Run workflow*, or `gh workflow run build-image`.

> Do NOT build `linux/amd64` on an Apple-Silicon Mac via `buildx` qemu: the x86_64 Nix installer **segfaults under qemu-user** (`qemu: uncaught target signal 11`). Build natively — GitHub Actions (above) or any native amd64 host (below).

### Fallback: build natively yourself — `build.sh`

On any native amd64 host:

```bash
echo "$GHCR_PAT" | docker login ghcr.io -u <github-user> --password-stdin   # PAT: write:packages
./build.sh
# → ghcr.io/<owner>/github-runner:2.336.0-noble  + :latest
```

## Point a runner at it

Wherever the runner is launched (its `docker run` / compose / systemd unit), change the image from:

```
myoung34/github-runner:2.336.0-ubuntu-noble
```

to:

```
ghcr.io/<owner>/github-runner:2.336.0-noble
```

Keep all existing runner configuration (repo/org URL, registration token, labels, ephemeral/one-job settings) unchanged. If the GHCR package is private, the host's Docker must be logged in to GHCR to pull it; making the package public removes that requirement.

## Per-repo workflow follow-up

Once a repo's CI runs on this image, drop its per-run Nix install so it uses the baked toolchain. Either:

- **Preferred — drop the action:** remove the `jetify-com/devbox-install-action` step; `devbox` is already on `PATH`, so `devbox run -- ...` steps work as-is. This also removes the Actions nix-store cache.
- **Or keep the action** with `skip-nix-installation: 'true'` (and drop `enable-cache: 'true'`).

## Caveats

- Assumes the runner executes jobs **as root** (base image default), so `/nix` is usable without a daemon. For a non-root runner user, start `nix-daemon` in an entrypoint or install Nix for that user's `HOME` instead.
- Bump the `FROM` tag + rebuild for a newer runner-agent version.

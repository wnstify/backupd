# Backupd test + coverage harness
#
# macOS can't run this suite natively (default bash 3.2 chokes on `declare -A`,
# and kcov is Linux-only), so all unit/integration/coverage runs happen here.
#
# Build:  docker build -t backupd-ci tests/docker
# Test:   docker run --rm -v "$PWD":/src -w /src backupd-ci ./tests/run-tests.sh --all
# Cover:  docker run --rm -v "$PWD":/src -w /src backupd-ci ./tests/run-tests.sh --coverage
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Test deps (shellcheck/jq/openssl/argon2), integration deps (sudo/restic/rclone/
# mariadb-client), and kcov build deps. kcov is NOT in the Ubuntu repos, so it is
# compiled from a pinned release tag below.
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
      shellcheck jq openssl argon2 ca-certificates sudo git \
      restic rclone mariadb-client \
      build-essential cmake libcurl4-openssl-dev libdw-dev libelf-dev \
      binutils-dev libiberty-dev zlib1g-dev libssl-dev python3 \
    && rm -rf /var/lib/apt/lists/*

# kcov pinned to v43 (latest stable; v44 is pre-release). Built from source for
# guaranteed glibc/arch compatibility (works on amd64 CI and arm64 locally).
RUN git clone --depth 1 --branch v43 https://github.com/SimonKagstrom/kcov /tmp/kcov \
    && cmake -S /tmp/kcov -B /tmp/kcov/build -DCMAKE_BUILD_TYPE=Release >/dev/null \
    && make -C /tmp/kcov/build -j"$(nproc)" >/dev/null \
    && make -C /tmp/kcov/build install >/dev/null \
    && rm -rf /tmp/kcov

CMD ["bash"]

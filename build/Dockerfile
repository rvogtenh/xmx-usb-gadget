FROM debian:bookworm
RUN apt-get update && apt-get install -y --no-install-recommends gcc make bc flex bison libssl-dev libelf-dev python3 kmod binutils ca-certificates xz-utils perl cpio && rm -rf /var/lib/apt/lists/*
WORKDIR /k

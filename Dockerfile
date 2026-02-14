FROM archlinux:latest

# Install build dependencies
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
        arch-install-scripts \
        parted dosfstools e2fsprogs \
        bsdtar curl zstd \
        bash coreutils util-linux && \
    pacman -Scc --noconfirm

WORKDIR /build
ENTRYPOINT ["/build/build.sh"]

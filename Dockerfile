FROM menci/archlinuxarm:latest

# Patch pacman.conf for Docker: disable Landlock sandbox and CheckSpace
# (Docker bind-mounts /etc/resolv.conf and /etc/hosts read-only).
# Must be a function since pacman -Syu can replace pacman.conf with .pacnew.
RUN patch_pacman() { \
        sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf; \
        sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf; \
    } && \
    patch_pacman && \
    pacman-key --init && pacman-key --populate archlinuxarm && \
    pacman -Syu --noconfirm && \
    patch_pacman && \
    pacman -S --noconfirm --needed \
        arch-install-scripts \
        parted dosfstools e2fsprogs \
        libarchive curl zstd \
        bash coreutils util-linux \
        multipath-tools && \
    pacman -Scc --noconfirm

WORKDIR /build
ENTRYPOINT ["/build/build.sh"]

FROM menci/archlinuxarm:latest

RUN sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf && \
    sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf && \
    pacman-key --init && pacman-key --populate archlinuxarm && \
    pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
        arch-install-scripts \
        parted dosfstools e2fsprogs \
        curl zstd \
        multipath-tools && \
    pacman -Scc --noconfirm

WORKDIR /build
ENTRYPOINT ["/build/build.sh"]

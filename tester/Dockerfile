FROM ghcr.io/nanake/fedora:rawhide

RUN <<EOF
  dnf config-manager setopt assumeyes=True install_weak_deps=False max_parallel_downloads=20
  dnf --nodocs in \
    wine-core \
    wine-common \
    diffutils \
    file \
    openssl
  dnf clean all
EOF

ENTRYPOINT ["/work/tests/test-libcurl.sh"]

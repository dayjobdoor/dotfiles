FROM ubuntu:26.04
ARG DJD_MODULES=agent
# DJD_NO_MUX: .zprofile would start herdr in every `docker run -it` login shell
ENV DEBIAN_FRONTEND=noninteractive DJD_NO_MUX=1
# `Defaults !admin_flag` stops sudo from creating ~/.sudo_as_admin_successful in the image
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git sudo zsh \
    && rm -rf /var/lib/apt/lists/* \
    && printf '%s\n' 'ubuntu ALL=(ALL) NOPASSWD:ALL' 'Defaults !admin_flag' > /etc/sudoers.d/ubuntu && chmod 0440 /etc/sudoers.d/ubuntu \
    && usermod -s /usr/bin/zsh ubuntu
# Packages and tools depend only on install.sh and mise-config. Copying those first keeps edits to
# dotfiles, docs and tests off the slow layer; the last install.sh run only links dotfiles.
COPY --chown=ubuntu:ubuntu install.sh /home/ubuntu/.dotfiles/install.sh
COPY --chown=ubuntu:ubuntu mise-config /home/ubuntu/.dotfiles/mise-config
USER ubuntu
WORKDIR /home/ubuntu
# The first RUN installs the packages without the GitHub token: apt maintainer scripts (Brave's deb) run as root
# in the environment of the mise process that called apt. Only the tools and the final hook (the HackGen download)
# reach GitHub, so only the second RUN mounts the token. mise bootstrap refills the apt lists; deleting them in
# this layer is what shrinks the image. The build runs as ubuntu (mise calls sudo itself), so the cleanup needs
# sudo too (DL3004).
# hadolint ignore=SC2086,DL3004
RUN DJD_BOOTSTRAP_FLAGS="--skip tools,final-hook,dotfiles" ~/.dotfiles/install.sh $DJD_MODULES \
    && sudo rm -rf /var/lib/apt/lists/*
RUN --mount=type=secret,id=github_token,env=MISE_GITHUB_TOKEN DJD_BOOTSTRAP_FLAGS="--only tools,final-hook" \
    ~/.dotfiles/install.sh
# Docker's default seccomp policy blocks namespace creation, so Brave aborts at startup unless it runs with
# --no-sandbox, which also disables its renderer seccomp-bpf sandbox. The container is the isolation boundary
# (SECURITY.md); VMs keep Brave's own sandbox because this override lives only here.
RUN if [ -f /usr/share/applications/brave-browser.desktop ]; then \
      mkdir -p ~/.local/share/applications \
      && sed -E 's/^(Exec=[^ ]+)/\1 --no-sandbox/' /usr/share/applications/brave-browser.desktop \
        > ~/.local/share/applications/brave-browser.desktop; \
    fi
COPY --chown=ubuntu:ubuntu . /home/ubuntu/.dotfiles
RUN DJD_BOOTSTRAP_FLAGS="--only dotfiles" ~/.dotfiles/install.sh
COPY --chmod=0755 .devcontainer/desktop-entrypoint.sh /usr/local/bin/djd-desktop-entrypoint
# shims on PATH for `docker run IMAGE cmd` and `docker exec`, which never read ~/.profile
ENV PATH=/home/ubuntu/.local/share/mise/shims:/home/ubuntu/.local/bin:$PATH
# the image has no .git (.dockerignore); `djd status` reports this commit instead. Declared last so a new
# commit never invalidates the cached layers above.
ARG DJD_REVISION=unknown
ENV DJD_REVISION=$DJD_REVISION
CMD ["zsh", "-l"]

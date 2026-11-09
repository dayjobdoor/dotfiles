FROM ubuntu:26.04
ARG DJD_MODULES=agent
# DJD_NO_MUX: .zprofile would start herdr in every `docker run -it` login shell
# LANG: `docker run` and `docker exec` read no ~/.profile, which sets it for login shells
ENV DEBIAN_FRONTEND=noninteractive DJD_NO_MUX=1 LANG=C.UTF-8
# `Defaults !admin_flag` stops sudo from creating ~/.sudo_as_admin_successful in the image
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git sudo zsh \
    && rm -rf /var/lib/apt/lists/* \
    && usermod -l dayjobdoor -d /home/dayjobdoor -m -s /usr/bin/zsh ubuntu && groupmod -n dayjobdoor ubuntu \
    && printf '%s\n' 'dayjobdoor ALL=(ALL) NOPASSWD:ALL' 'Defaults !admin_flag' > /etc/sudoers.d/dayjobdoor && chmod 0440 /etc/sudoers.d/dayjobdoor
# Packages and tools depend only on install.sh, its wrapper and mise-config. Copying those first keeps edits to
# dotfiles, docs and tests off the slow layer; the last install.sh run only links dotfiles.
COPY --chown=dayjobdoor:dayjobdoor install.sh /home/dayjobdoor/.dotfiles/install.sh
COPY --chown=dayjobdoor:dayjobdoor home/.local/bin/djd /home/dayjobdoor/.dotfiles/home/.local/bin/djd
COPY --chown=dayjobdoor:dayjobdoor mise-config /home/dayjobdoor/.dotfiles/mise-config
USER dayjobdoor
WORKDIR /home/dayjobdoor
# The first RUN does everything that runs apt or other root scripts, without the GitHub token: apt maintainer
# scripts (Brave's deb) run as root in the environment of the mise process that called apt, and so does the final
# hook's `apt-get purge`. Only the tools reach GitHub (they download releases), so only the second RUN mounts the
# token. mise bootstrap refills the apt lists; deleting them in this layer is what shrinks the image. The build
# runs as dayjobdoor (mise calls sudo itself), so the cleanup needs sudo too (DL3004). SC2086: $DJD_MODULES is a list
# of words on purpose.
# hadolint ignore=SC2086,DL3004
RUN DJD_BOOTSTRAP_FLAGS="--skip tools,dotfiles" ~/.dotfiles/install.sh $DJD_MODULES \
    && sudo rm -rf /var/lib/apt/lists/*
RUN --mount=type=secret,id=github_token,env=MISE_GITHUB_TOKEN DJD_BOOTSTRAP_FLAGS="--only tools" \
    ~/.dotfiles/install.sh
# Docker's default seccomp policy blocks namespace creation, so Brave aborts at startup unless it runs with
# --no-sandbox, which also disables its renderer seccomp-bpf sandbox. The container is the isolation boundary
# (SECURITY.md); VMs keep Brave's own sandbox because this override lives only here.
RUN if [ -f /usr/share/applications/brave-browser.desktop ]; then \
      mkdir -p ~/.local/share/applications \
      && sed -E 's/^(Exec=[^ ]+)/\1 --no-sandbox/' /usr/share/applications/brave-browser.desktop \
        > ~/.local/share/applications/brave-browser.desktop; \
    fi
# The same holds for the Electron apps, whose menu entries the tools phase wrote.
RUN for f in obsidian ferdium; do \
      if [ -f ~/.local/share/applications/$f.desktop ]; then \
        sed -i -E 's/^(Exec=[^ ]+)/\1 --no-sandbox/' ~/.local/share/applications/$f.desktop; \
      fi; \
    done
COPY --chown=dayjobdoor:dayjobdoor . /home/dayjobdoor/.dotfiles
# The same RUN fetches the zsh plugins at the revisions that ~/.config/sheldon/plugins.toml pins (the final hook does that
# on a VM, after the tools; here the tools came in a pass of their own, and the ENV PATH below does not exist yet).
RUN DJD_BOOTSTRAP_FLAGS="--only dotfiles" ~/.dotfiles/install.sh \
    && ~/.local/share/mise/shims/sheldon lock
COPY --chmod=0755 .devcontainer/desktop-entrypoint.sh /usr/local/bin/djd-desktop-entrypoint
# shims on PATH for `docker run IMAGE cmd` and `docker exec`, which never read ~/.profile
ENV PATH=/home/dayjobdoor/.local/share/mise/shims:/home/dayjobdoor/.local/bin:$PATH
# the image has no .git (Dockerfile.dockerignore); `djd status` reports this commit instead. Declared last so a new
# commit never invalidates the cached layers above.
ARG DJD_REVISION=unknown
ENV DJD_REVISION=$DJD_REVISION
CMD ["zsh", "-l"]

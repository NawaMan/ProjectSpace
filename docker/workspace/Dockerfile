# syntax=docker/dockerfile:1.7
ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

ENV DEBIAN_FRONTEND=noninteractive
ARG LOCALE=en_US.UTF-8

RUN apt-get update -qq      \
 && apt-get install -y      \
    --no-install-recommends \
    bash                    \
    ca-certificates         \
    curl                    \
    git                     \
    gosu                    \
    jq                      \
    less                    \
    locales                 \
    nano                    \
    python3                 \
    python3-pip             \
    python3-venv            \
    sudo                    \
    tini                    \
    tree                    \
    unzip                   \
    wget                    \
    zip                     \
    zsh                     \
 && rm -rf /var/lib/apt/lists/* \
 && sed -i "/${LOCALE}/s/^# //g" /etc/locale.gen && locale-gen "${LOCALE}"

# Fixed values (name & paths). UID/GID come from HOST_UID/HOST_GID at runtime.
ENV USER_NAME=coder                   \
    HOME=/home/coder                  \
    LANG=${LOCALE}                    \
    LC_ALL=${LOCALE}                  \
    WORKSPACE=/home/coder/workspace   \
    PATH=/home/coder/.local/bin:$PATH

# Entry that aligns coder’s uid/gid to host, then drops privileges
COPY --chmod=0755 entry-script /usr/local/bin/entry-script

WORKDIR /home/coder/workspace
SHELL ["/bin/bash","-lc"]

# Seed dirs; ownership finalized at runtime
RUN mkdir -p /home/coder/workspace /home/coder/.local/share/jupyter/runtime

# --- Shared shell config: create the file (heredoc in its own RUN) ---
RUN cat >/etc/profile.d/99-custom.sh <<'EOF'
# ---- container defaults (safe to source multiple times) ----
# Aliases
alias cat=ccat
alias cp='cp -p'
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias tree='tree -C'

# Environment
export EDITOR=nano
export PIP_DISABLE_PIP_VERSION_CHECK=1
# ---- end defaults ----
EOF

# --- Make bash and zsh source it (separate RUN avoids heredoc-continue issues) ---
RUN set -eux; \
  if ! grep -q 'profile.d/99-custom.sh' /etc/bash.bashrc 2>/dev/null; then \
    echo '[ -f /etc/profile.d/99-custom.sh ] && . /etc/profile.d/99-custom.sh' >> /etc/bash.bashrc; \
  fi; \
  mkdir -p /etc/zsh; \
  : > /etc/zsh/zshrc; \
  if ! grep -q 'profile.d/99-custom.sh' /etc/zsh/zshrc 2>/dev/null; then \
    echo '[[ -f /etc/profile.d/99-custom.sh ]] && source /etc/profile.d/99-custom.sh' >> /etc/zsh/zshrc; \
  fi

# tini as PID 1, then run the aligner which execs as 'coder'
ENTRYPOINT ["tini","-g","--","/usr/local/bin/entry-script"]
CMD ["bash"]

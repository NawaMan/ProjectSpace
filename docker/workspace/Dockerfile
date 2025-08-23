# syntax=docker/dockerfile:1.7

# Dockerfile for workspace (the base)

ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

ENV DEBIAN_FRONTEND=noninteractive
ARG LOCALE=en_US.UTF-8

# Safer default shell
SHELL ["/bin/bash","-o","pipefail","-lc"]

# Update base OS, install packages, generate locale
RUN set -eux; \
  apt-get update -qq; \
  apt-get -y upgrade; \
  apt-get install -y \
    --no-install-recommends \
    bash            \
    ca-certificates \
    curl            \
    git             \
    jq              \
    less            \
    locales         \
    nano            \
    python3         \
    python3-pip     \
    python3-venv    \
    sudo            \
    tini            \
    tree            \
    unzip           \
    wget            \
    zip             \
    zsh;            \
  rm -rf /var/lib/apt/lists/*; \
  sed -i "/${LOCALE}/s/^# //g" /etc/locale.gen && locale-gen "${LOCALE}"

# Fixed values (name & paths). UID/GID come from HOST_UID/HOST_GID at runtime.
ENV USER_NAME=coder \
    HOME=/home/coder \
    LANG=${LOCALE} \
    LC_ALL=${LOCALE} \
    WORKSPACE=/home/coder/workspace

# Create a Python venv and upgrade pip/setuptools/wheel (addresses setuptools CVEs)
# Clean any pip caches explicitly, then make the venv default.
RUN python3 -m venv /opt/venv \
 && /opt/venv/bin/python -m pip install --upgrade pip setuptools wheel \
 && rm -rf /root/.cache/pip

# Make the venv default and set pip knobs AFTER the upgrade above
ENV PATH=/opt/venv/bin:/home/coder/.local/bin:$PATH \
    EDITOR=nano \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

# Entry that aligns coder’s uid/gid to host, then drops privileges
COPY --chmod=0755 entry-script /usr/local/bin/entry-script

WORKDIR /home/coder/workspace

# Seed dirs; ownership finalized at runtime
RUN mkdir -p /home/coder/workspace /home/coder/.local/share/jupyter/runtime

# --- Shared shell config: create the file ---
RUN cat >/etc/profile.d/99-custom.sh <<'EOF'
# ---- container defaults (safe to source multiple times) ----
alias cp='cp -p'
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias tree='tree -C'
# Environment
export EDITOR=${EDITOR:-nano}
export PIP_DISABLE_PIP_VERSION_CHECK=1
# ---- end defaults ----
EOF

# --- Make bash and zsh source it ---
RUN set -eux; \
  grep -q 'profile.d/99-custom.sh' /etc/bash.bashrc 2>/dev/null || \
    echo '[ -f /etc/profile.d/99-custom.sh ] && . /etc/profile.d/99-custom.sh' >> /etc/bash.bashrc; \
  mkdir -p /etc/zsh; \
  : > /etc/zsh/zshrc; \
  grep -q 'profile.d/99-custom.sh' /etc/zsh/zshrc 2>/dev/null || \
    echo '[[ -f /etc/profile.d/99-custom.sh ]] && source /etc/profile.d/99-custom.sh' >> /etc/zsh/zshrc

# tini as PID 1, then run the aligner which execs as 'coder'
ENTRYPOINT ["tini","-g","--","/usr/local/bin/entry-script"]
CMD ["bash"]

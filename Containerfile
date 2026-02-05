FROM manjarolinux/base:latest

COPY certs/cert.crt /etc/ca-certificates/trust-source/anchors/cert.crt

# Switch to HTTP mirrors to avoid SSL issues in certain network environments and update certificates
RUN pacman-mirrors --api -P http --country all && \
    pacman -Syyu --noconfirm && \
    pacman -S --noconfirm --needed ca-certificates && \
    pacman -Scc --noconfirm && \
    trust extract-compat && \
    rm /etc/ca-certificates/trust-source/anchors/cert.crt

# Setup keys for pacman 
RUN pacman -Sy --noconfirm haveged && \
    haveged -w 1024 && \
    rm -rf /etc/pacman.d/gnupg && \
    pacman-key --init && \
    pacman-key --populate archlinux manjaro && \
    pacman -Scc --noconfirm

# Install base development tools and git early
RUN pacman -Syu --needed --noconfirm base-devel git sudo && \
    pacman -Scc --noconfirm

# Create user early for AUR installations
RUN usermod -d /home/builder -m builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Set locale and timezone
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV TZ=Asia/Kolkata

# Configure locale
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen && \
    echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Switch to builder user for AUR helper installation
USER builder
WORKDIR /home/builder

# Setup git
ARG user=builder
ARG group=builder
ARG uid=1000
ARG gid=1000
ARG email=vishal.reply@gmail.com
ARG name="Vishal Saxena"
ARG homedir=/home/${user}
COPY --chown=${user}:${group} gh/gh.gpg ${homedir}/.secrets/gh.gpg
COPY --chown=${user}:${group} --chmod=755 gh/gh-cred-helper.sh ${homedir}/.secrets/gh-cred-helper.sh
COPY --chown=${user}:${group} certs/cert.crt certs/cert.pem ${homedir}/.certs/
ENV SHELL=/bin/bash
RUN git config --global core.editor nvim \
    && git config --global init.defaultBranch main \
    && git config --global pull.rebase true \
    && git config --global user.email ${email} \
    && git config --global user.name ${name} \
    && git config --global credential.helper ${homedir}/.secrets/gh-cred-helper.sh 

# Install mise
RUN curl https://mise.run/bash | sh && \
mkdir -p ${homedir}/.config/mise
ENV MISE_INSTALL_PATH=${homedir}/.local/bin
ENV PATH=${MISE_INSTALL_PATH}:${PATH}

# Setup AUR helper (yay)
RUN git clone https://aur.archlinux.org/yay-bin.git && \
    cd yay-bin && \
    makepkg -si --noconfirm && \
    cd .. && \
    rm -rf yay-bin && \
    yay -Syu --noconfirm && \
    yay -Scc --noconfirm

# Setup node
ENV NODE_EXTRA_CA_CERTS=${homedir}/.certs/cert.pem
RUN mise use -g node@lts 
RUN mise use -g npm:npm 
RUN mise use -g npm:typescript 
RUN mise use -g npm:tree-sitter-cli 
RUN mise use -g npm:neovim

# Setup single editor neovim 
ENV EDITOR=nvim
ENV VISUAL=nvim
ENV XDG_CONFIG_HOME=${homedir}/.config
ENV COLORTERM=truecolor
ENV PATH="${homedir}/.local/share/bob/nvim-bin:${PATH}"

RUN yay -Sy --noconfirm fd ripgrep unzip xclip bob && \
    yay -Scc --noconfirm && \
    git clone https://github.com/vishalgit/kickstart.nvim /home/${user}/.config/kickstart && \
    cd /home/${user}/.config/kickstart && \
    git remote add upstream https://github.com/nvim-lua/kickstart.nvim && \
    git remote set-url --push upstream DISABLE && \
    echo "alias kvim='NVIM_APPNAME=kickstart nvim'" >> ${homedir}/.bashrc && \
    bob use stable
# Enable kata
ARG kata_location=${homedir}/.local/bin
RUN git clone https://github.com/vishalgit/vim-kata && mv vim-kata ${homedir}/.vim-kata && \
    printf "#!/bin/bash\n" > ${kata_location}/kata && \
    printf "export NVIM_APPNAME=kickstart\n" >> ${kata_location}/kata && \    
    printf "cd "${homedir}"/.vim-kata\n" >> ${kata_location}/kata && \
    printf "./run.sh\n" >> ${kata_location}/kata && \
    chmod u+x ${kata_location}/kata

# Setup rclone
COPY --chown=${user}:${group} rclone.conf ${XDG_CONFIG_HOME}/rclone/rclone.conf
RUN mise use -g aqua:rclone/rclone

# Setup tools
RUN mise use -g aqua:jqlang/jq
RUN mise use -g aqua:sharkdp/bat
RUN mise use -g aqua:eth-p/bat-extras
RUN mise use -g aqua:sxyazi/yazi
# Setup aliases
RUN printf "alias gitdc='gpg --decrypt "${homedir}"/.secrets/gh.gpg'\n" >> /home/${user}/.bashrc && \
printf "alias orgbisync='rclone bisync "${homedir}"/org mega:org --resync --size-only'\n" >> /home/${user}/.bashrc && \
printf "alias orgsync='rclone sync "${homedir}"/org mega:org'\n" >> /home/${user}/.bashrc && \
mkdir -p ${homedir}/org
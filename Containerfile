FROM manjarolinux/base:latest

COPY certs/cert.crt /etc/ca-certificates/trust-source/anchors/cert.crt

# Switch to HTTP mirrors to avoid SSL issues in certain network environments and update certificates
RUN sed -i 's|https://|http://|g' /etc/pacman.d/mirrorlist && \
pacman -Syyu --noconfirm && \
pacman -S --noconfirm --needed ca-certificates && \
pacman -Scc --noconfirm && \
trust extract-compat && \
rm /etc/ca-certificates/trust-source/anchors/cert.crt && \
sed -i 's|http://|https://|g' /etc/pacman.d/mirrorlist 

# Setup keys for pacman 
RUN pacman -Sy --noconfirm haveged && \
haveged -w 1024 && \
rm -rf /etc/pacman.d/gnupg && \
pacman-key --init && \
pacman-key --populate archlinux manjaro && \
pacman -Scc --noconfirm

# Install base development tools and git early (needed for paru)
RUN pacman -S --needed --noconfirm base-devel git sudo && \
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
# Install paru AUR helper as builder user
RUN cd /tmp && \
git clone https://aur.archlinux.org/paru.git && \
cd paru && \
makepkg -si --noconfirm && \
rm -rf /tmp/paru

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
ENV SHELL=/bin/zsh
RUN git config --global core.editor nvim \
&& git config --global init.defaultBranch main \
&& git config --global pull.rebase true \
&& git config --global user.email ${email} \
&& git config --global user.name ${name} \
&& git config --global credential.helper ${homedir}/.secrets/gh-cred-helper.sh 

# Setup oh-my-zsh
RUN paru -S --noconfirm \
zsh \
wget \
fzf \
ttf-jetbrains-mono-nerd \
ttf-nerd-fonts-symbols && \ 
mkdir -p /home/${user}/.config/ezsh && \
git clone https://github.com/vishalgit/ezsh ezsh \
&& touch .zshrc \
&& cd ezsh \
&& chmod +x install.sh \
&& ./install.sh -n \
&& cd \
&& rm -rf ezsh \
&& sudo chsh -s /bin/zsh builder \
&& paru -Scc --noconfirm

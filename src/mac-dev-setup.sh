#!/bin/bash

# This script is idempotent: it can be re-run safely any number of times.

# Create a folder who contains downloaded things for the setup
INSTALL_FOLDER=~/.macsetup
mkdir -p "$INSTALL_FOLDER"
MAC_SETUP_PROFILE=$INSTALL_FOLDER/macsetup_profile

# This script fully owns the profile file: regenerate it from scratch on every
# run so re-running never duplicates lines. Don't edit it by hand.
: >"$MAC_SETUP_PROFILE"

# Keep brew non-interactive: no "Do you want to proceed?" per install, no env hints
export HOMEBREW_NO_ASK=1
export HOMEBREW_NO_ENV_HINTS=1

# install brew
if ! command -v brew >/dev/null 2>&1
then
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  printf "\e[93m%s\e[m\n" "You already have brew installed."
fi

# Detect Homebrew installation path (default is /opt/homebrew/bin for ARM Macs and /usr/local/bin for Intel Macs)
DEFAULT_BREW_PATHS=("/opt/homebrew/bin" "/usr/local/bin")

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found in PATH."
  for path in "${DEFAULT_BREW_PATHS[@]}"; do
    if [ -x "$path/brew" ]; then
      export PATH="$path:$PATH"
      break
    fi
  done
fi

BREW_PREFIX="$(brew --prefix)"
echo "export PATH=\"$BREW_PREFIX/bin:\$PATH\"" >>"$MAC_SETUP_PROFILE"

brew update

# CURL / WGET
brew install curl
brew install wget

{
  echo "export PATH=\"$BREW_PREFIX/opt/curl/bin:\$PATH\""
  echo "export PATH=\"$BREW_PREFIX/opt/sqlite/bin:\$PATH\""
}>>"$MAC_SETUP_PROFILE"

# git
brew install git                                                                                      # https://formulae.brew.sh/formula/git
# Adding git aliases (https://github.com/thomaspoignant/gitalias)
# git clone https://github.com/thomaspoignant/gitalias.git $INSTALL_FOLDER/gitalias && echo -e "[include]\n    path = $INSTALL_FOLDER/gitalias/.gitalias\n$(cat ~/.gitconfig)" > ~/.gitconfig

brew install gh
if ! gh auth status >/dev/null 2>&1; then
  gh auth login
fi

SSH_KEY="$HOME/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY" ]; then
  ssh-keygen -t ed25519 -C "kovachevd98@gmail.com" -f "$SSH_KEY" -N ""
fi

# Add the public key to your GitHub account (skip if this key is already there)
if ! gh ssh-key list 2>/dev/null | grep -qF "$(awk '{print $2}' "${SSH_KEY}.pub")"; then
  gh ssh-key add "${SSH_KEY}.pub" --title "$(hostname)-setup"
fi

# Ensure SSH config exists and sets GitHub to use your key
SSH_CONFIG="$HOME/.ssh/config"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if ! grep -q "Host github.com" "$SSH_CONFIG" 2>/dev/null; then
  cat >> "$SSH_CONFIG" <<EOF

Host *
  SendEnv LANG
  SetEnv TERM=xterm-256color

Host github.com
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_ed25519
EOF
  chmod 600 "$SSH_CONFIG"
fi

# dotfiles (a function instead of an alias: aliases don't expand in non-interactive bash)
dotfiles() {
  git --git-dir="$HOME/.dotfiles" --work-tree="$HOME" "$@"
}
if [ ! -d "$HOME/.dotfiles" ]; then
  git clone --bare git@github.com:dimitarkovachev/.dotfiles.git "$HOME/.dotfiles"
  dotfiles checkout
fi
dotfiles config --local status.showUntrackedFiles no
echo "alias dotfiles='git --git-dir=\$HOME/.dotfiles --work-tree=\$HOME'" >>"$MAC_SETUP_PROFILE"

# brew install git-secrets                                                                              # git hook to check if you are pushing aws secret (https://github.com/awslabs/git-secrets)
# git secrets --register-aws --global
# git secrets --install ~/.git-templates/git-secrets
# git config --global init.templateDir ~/.git-templates/git-secrets

# ZSH
brew install zsh                                                                     # Install zsh and zsh completions
# Make completion dirs group/other non-writable so zsh compaudit is happy.
# (No sudo chown here: brew must stay owner of its own dirs or every later install breaks.)
if [ -d "$BREW_PREFIX/share/zsh" ]; then
  chmod -R go-w "$BREW_PREFIX/share/zsh"
fi

# Install oh-my-zsh on top of zsh to getting additional functionality
# --unattended: don't switch shell / drop into zsh mid-script; KEEP_ZSHRC=yes: don't touch the .zshrc coming from dotfiles
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi
ZSH="${ZSH:-$HOME/.oh-my-zsh}"
ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH/custom}"

# Terminal replacement https://cmux.com/
brew install --cask cmux
brew install fzf

# Pimp command line
# brew install micro                                                                                    # replacement for nano/vi
# brew install lsd                                                                                      # replacement for ls
{
  echo "alias ls='lsd'"
  echo "alias l='ls -l'"
  echo "alias la='ls -a'"
  echo "alias lla='ls -la'"
  echo "alias lt='ls --tree'"
} >>"$MAC_SETUP_PROFILE"

brew install tree
# brew install ack
brew install bash-completion
brew install jq
brew install htop
brew install tldr
brew install coreutils
brew install watch

brew install z
touch ~/.z
echo ". $BREW_PREFIX/etc/profile.d/z.sh" >> "$MAC_SETUP_PROFILE"

brew install ctop

# fonts (https://github.com/tonsky/FiraCode/wiki/Intellij-products-instructions)
# brew tap homebrew/cask-fonts
# brew install --cask font-jetbrains-mono

# Browser
# brew install --cask google-chrome
# brew install --cask firefox
# brew install --cask microsoft-edge
brew install --cask zen

# Music / Video
# brew install --cask spotify
# brew install --cask vlc

# Productivity
# brew install --cask evernote                                                                            # cloud note
# brew install --cask kap                                                                                 # video screenshot
brew install --cask rectangle                                                                           # manage windows
brew install --cask alt-tab
brew install --cask alfred
# brew install --cask karabiner-elements

# macOS system settings
## Dock: nothing pinned, hide when the mouse isn't on it
defaults write com.apple.dock persistent-apps -array
defaults write com.apple.dock persistent-others -array
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock autohide -bool true
killall Dock 2>/dev/null || true

## Battery > Options: prevent automatic sleeping on power adapter when the display is off
sudo pmset -c sleep 0 || true

# Communication
# brew install --cask slack
# brew install --cask whatsapp

# Dev tools
brew install --cask ngrok                                                                               # tunnel localhost over internet.
brew install --cask postman                                                                             # Postman makes sending API requests simple.

# IDE
# brew install --cask jetbrains-toolbox
brew install --cask vscodium

{
  echo "alias code='codium'"
  echo "export EDITOR='codium -w'"
} >>"$MAC_SETUP_PROFILE"

# the extensions list comes from the dotfiles checkout (earlier in this script)
if [ -f "$HOME/code_extensions.txt" ]; then
  xargs -L 1 codium --install-extension <"$HOME/code_extensions.txt"
else
  echo "WARN: $HOME/code_extensions.txt not found - skipping codium extensions"
fi

# Language
## Node / Javascript
mkdir -p ~/.nvm
brew install nvm                                                                                     # choose your version of npm
{
  echo "export NVM_DIR=\"\$HOME/.nvm\""
  echo "[ -s \"$BREW_PREFIX/opt/nvm/nvm.sh\" ] && . \"$BREW_PREFIX/opt/nvm/nvm.sh\""
} >>"$MAC_SETUP_PROFILE"
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1091
source "$BREW_PREFIX/opt/nvm/nvm.sh"                                                                 # nvm is a shell function, load it for this script
nvm install node                                                                                     # "node" is an alias for the latest version
brew install yarn                                                                                    # Dependencies management for node

# npm i -g opencode-ai@latest
brew install --cask claude                                                                           # Claude desktop app
curl -fsSL https://claude.ai/install.sh | bash                                                       # Claude Code CLI -> ~/.local/bin
echo "export PATH=\"\$HOME/.local/bin:\$PATH\" # claude code" >>"$MAC_SETUP_PROFILE"

## Java
if [ ! -d "$HOME/.sdkman" ]; then
  curl -s "https://get.sdkman.io" | zsh                                                              # sdkman is a tool to manage multiple version of java
fi
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk install java
# also install latest Temurin 21 (LTS); resolve the exact version from sdkman's list
JAVA21_TEM="$(sdk list java 2>/dev/null | grep -o '21\.[0-9]*\.[0-9]*-tem' | head -1 || true)"
if [ -n "$JAVA21_TEM" ]; then
  sdk install java "$JAVA21_TEM" <<<"n" # "n" answers the "set as default?" prompt: latest stays default
else
  echo "WARN: could not resolve a 21.x-tem version from 'sdk list java' - skipping Java 21"
fi
sdk install gradle
# brew install maven

## golang
{
  echo "# Go development"
  echo "export GOPATH=\"\${HOME}/.go\""
  echo "export GOROOT=\"\$(brew --prefix golang)/libexec\""
  echo "export PATH=\"\$PATH:\${GOPATH}/bin:\${GOROOT}/bin\""
}>>"$MAC_SETUP_PROFILE"
brew install go

## python
echo "export PATH=\"$BREW_PREFIX/opt/python/libexec/bin:\$PATH\"" >> "$MAC_SETUP_PROFILE"
brew install python
export PATH="$BREW_PREFIX/opt/python/libexec/bin:$PATH"
# brew's python is externally managed (PEP 668): no bare "pip install" into it
brew install pipenv
brew install pipx
brew install pyenv
# shellcheck disable=SC2016
echo 'eval "$(pyenv init -)"' >> "$MAC_SETUP_PROFILE"


## terraform (no longer in homebrew-core since the BUSL license change -> hashicorp tap)
brew tap hashicorp/tap
brew trust hashicorp/tap 2>/dev/null || true # Homebrew >=6 requires trusting third-party taps
brew install hashicorp/tap/terraform
terraform -v

# Databases
brew install --cask dbeaver-community # db viewer
brew install libpq                  # postgre command line
brew link --force libpq
echo "export PATH=\"$BREW_PREFIX/opt/libpq/bin:\$PATH\"" >> "$MAC_SETUP_PROFILE"

# SFTP
# brew install --cask cyberduck

# Docker

# brew install --cask docker
# brew install bash-completion
# brew install docker-completion
# brew install docker-compose-completion
# brew install docker-machine-completion

# AWS command line
# brew install awscli # Official command line
# pip3 install saws    # A supercharged AWS command line interface (CLI).

# K8S command line
brew install kubectx
brew install asdf
echo "export PATH=\"\$HOME/.asdf/shims:\$PATH\"" >>"$MAC_SETUP_PROFILE"
export PATH="$HOME/.asdf/shims:$PATH"
asdf plugin add kubectl 2>/dev/null || true
asdf install kubectl latest
asdf set -u kubectl latest 2>/dev/null || asdf global kubectl latest 2>/dev/null || true

clone_zsh_plugin() {
  local repo="$1" dest="$2"
  [ -d "$dest" ] || git clone --depth 1 -- "$repo" "$dest"
}
clone_zsh_plugin https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
clone_zsh_plugin https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
clone_zsh_plugin https://github.com/zdharma-continuum/fast-syntax-highlighting.git "$ZSH_CUSTOM/plugins/fast-syntax-highlighting"
clone_zsh_plugin https://github.com/marlonrichert/zsh-autocomplete.git "$ZSH_CUSTOM/plugins/zsh-autocomplete"

{
  echo "plugins=(git grc zsh-autosuggestions zsh-syntax-highlighting fast-syntax-highlighting zsh-autocomplete)"

  echo "source $ZSH/oh-my-zsh.sh"
}>>"$MAC_SETUP_PROFILE"

# hook the generated profile into .zsh_profile (once)
ZSH_PROFILE="$HOME/.zsh_profile"
touch "$ZSH_PROFILE"
if ! grep -qF "source $MAC_SETUP_PROFILE" "$ZSH_PROFILE"; then
  echo "source $MAC_SETUP_PROFILE # alias and things added by mac_setup script" >>"$ZSH_PROFILE"
fi

# make sure .zshrc actually loads .zsh_profile and .zsh_funcs
# (.zsh_profile is not a file zsh reads on its own; skip if the dotfiles .zshrc already sources them)
touch "$HOME/.zshrc"
if ! grep -q "\.zsh_profile" "$HOME/.zshrc"; then
  echo '[ -f ~/.zsh_profile ] && source ~/.zsh_profile' >>"$HOME/.zshrc"
fi
if ! grep -q "\.zsh_funcs" "$HOME/.zshrc"; then
  echo '[ -f ~/.zsh_funcs ] && source ~/.zsh_funcs' >>"$HOME/.zshrc"
fi

echo "Done! Open a new terminal (or 'source ~/.zshrc') to pick up the changes."

# plugins=(git zsh-autosuggestions zsh-syntax-highlighting fast-syntax-highlighting zsh-autocomplete)
# macos text navigation shortcuts
# Go to iTerm2>Settings>Profiles>Keys>Key Mappings and from the preset dropdown on the bottom select Natural Text Editing

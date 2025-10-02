# Oh-my-zsh installation path, theme and other settings:
export ZSH="${HOME}/.oh-my-zsh"
ZSH_THEME="spaceship"
SPACESHIP_BATTERY_PREFIX=" "
SPACESHIP_PROMPT_ADD_NEWLINE="false"
SPACESHIP_PROMPT_SEPARATE_LINE="false"
plugins=(git)
source $ZSH/oh-my-zsh.sh

# Ensure that the PATH array stores unique values:
typeset -U path

# Make commonly-used tools globally accessible:
path+=${HOME}/scripts

# Add Rust package executables to PATH:
if [[ -d ${HOME}/.cargo/bin ]]; then
    path+=${HOME}/.cargo/bin
fi

# Perform MacOS-specific actions:
if [[ ${OSTYPE} == "darwin"* ]]; then
    # We don't want Homebrew talking to Google Analytics.
    export HOMEBREW_NO_ANALYTICS=1
    # Add Homebrew executables to PATH:
    path=(/opt/homebrew/bin $path)
    path=(/opt/homebrew/sbin $path)
    # Add Go package executables to PATH:
    if [ -d /opt/homebrew/opt/go ]; then
        export GOPATH="${HOME}/golang"
        export GOROOT="/opt/homebrew/opt/go/libexec"
        path+=${GOROOT}/bin
        path+=${GOPATH}/bin
    fi
    # Add LLVM executables to PATH:
    if [ -d /opt/homebrew/opt/llvm ]; then
        path+=/opt/homebrew/opt/llvm/bin
    fi
fi

# Use the "lsd" utility, if it exists, instead of the default one:
if type lsd > /dev/null 2>&1; then
    alias ls=lsd
# Otherwise, use the color option of "ls":
elif [[ ${OSTYPE} == "linux-gnu" ]]; then
    alias ls="ls --color=always"
elif [[ ${OSTYPE} == "darwin"* ]]; then
    alias ls="ls -G"
fi

# Use the color option of "grep" and "less":
# alias grep="grep --color=always"
# alias less="less -R"

# Make sure tmux uses the correct colors. Also, in order to avoid breaking
# chroots, urge tmux to create its socket under ${HOME}.
alias tmux="mkdir -p ${HOME}/tmp; tmux -2 -S ${HOME}/tmp/default"

# Make sure we use VIM as the default editor.
export VISUAL=vim
export EDITOR=vim

# Various Java tools require this to be set up to work.
if [ -f "/usr/libexec/java_home" ]; then
    export JAVA_HOME=$(/usr/libexec/java_home)
fi

# Load xmake profile:
if [ -s ~/.xmake/profile ]; then
    source ~/.xmake/profile
fi

# Use FZF if it exists:
if [ -f ~/.fzf.zsh ]; then
    source ~/.fzf.zsh
fi

# Activate my Python environment:
source ~/pyenv/bin/activate


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
path+=/usr/local/sbin
if [[ ${OSTYPE} == "darwin"* ]]; then
    if [ -d /usr/local/opt/go ]; then
        export GOPATH="${HOME}/golang"
        export GOROOT="/usr/local/opt/go/libexec"
        path+=${GOROOT}/bin
        path+=${GOPATH}/bin
    fi
    if [ -d /usr/local/opt/llvm ]; then
        path+=/usr/local/opt/llvm/bin
    fi
fi

# Make sure tmux uses the correct colors. Also, in order to avoid breaking
# chroots, urge tmux to create its socket under ${HOME}.
alias tmux="mkdir -p ${HOME}/tmp; tmux -2 -S ${HOME}/tmp/default"

# Make sure we use VIM as the default editor.
export VISUAL=vim
export EDITOR=vim

# We don't want Homebrew talking to Google Analytics.
export HOMEBREW_NO_ANALYTICS=1

# Enable iTerm2 back-end for Matplotlib.
export MPLBACKEND="module://itermplot"
# Reverse Matplotlib colors to accomodate my terminal's dark background.
export ITERMPLOT=rv

# Various Java tools require this to be set up to work.
if [ -f "/usr/libexec/java_home" ]; then
    export JAVA_HOME=$(/usr/libexec/java_home)
fi

# Use FZF if it exists:
if [ -f ~/.fzf.zsh ]; then
    source ~/.fzf.zsh
fi


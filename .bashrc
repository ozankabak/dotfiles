#!/bin/bash

idempotentAdd() {
    # Extend given PATH-type variable in an idempotent way.
    # $1 = Either the string "append" or the string "prepend".
    # $2 = Name of the PATH-type variable.
    # $3 ... $N = Directories to be added.

    # If we don't have all the arguments we need or mode is unrecognized, return:
    if [ ${#} -le 2 ] || ! [[ ${1} == "append" || ${1} == "prepend" ]]; then
        return -1
    fi

    # If the given PATH-type variable is empty, we will create it:
    if [ -z ${!2} ]; then
        # Concatenate all arguments with colons, write to the output variable:
        printf -v ${2} ":%s" ${@:3}
        # Remove the spurious first colon.
        printf -v ${2} "%s" ${!2:1}
        return -1
    fi

    if [[ ${1} == "append" ]]; then
        for VAR in ${@:3}; do
            idempotentAddSingle ${1} ${2} ${VAR}
        done
    else
        for ((ind=$#; ind>=3; ind--)); do
            idempotentAddSingle ${1} ${2} ${!ind}
        done
    fi
}

idempotentAddSingle() {
    # If the given PATH-type variable already contains the to-be-added directory,
    # return. This check makes the function idempotent.
    if [[ :${!2}: == *":${3}:"* ]]; then
        return
    fi
    # Append, or prepend, to the given PATH-type variable.
    case ${1} in
        "prepend") printf -v ${2} "%s" "${3}:${!2}" ;;
        *)         printf -v ${2} "%s" "${!2}:${3}" ;;
    esac
}

# Make commonly-used tools globally accessible:
idempotentAdd "append" "PATH" "${HOME}/scripts"
idempotentAdd "append" "PATH" "/usr/local/sbin"
if [[ ${OSTYPE} == "darwin"* ]]; then
    if [ -d /usr/local/opt/go ]; then
        export GOPATH="${HOME}/golang"
        export GOROOT="/usr/local/opt/go/libexec"
        idempotentAdd "append" "PATH" "${GOROOT}/bin"
        idempotentAdd "append" "PATH" "${GOPATH}/bin"
    fi
    if [ -d /usr/local/opt/llvm ]; then
        idempotentAdd "append" "PATH" "/usr/local/opt/llvm/bin"
    fi
fi

# Let there be colors:
if [[ ${OSTYPE} == "linux-gnu" ]]; then
    alias ls="ls --color=always"
elif [[ ${OSTYPE} == "darwin"* ]]; then
    alias ls="ls -G"
fi
alias grep="grep --color=always"
alias less="less -R"

# Make sure tmux uses the correct colors. Also, in order to avoid breaking
# chroots, urge tmux to create its socket under ${HOME}.
alias tmux="mkdir -p ${HOME}/tmp; tmux -2 -S ${HOME}/tmp/default"

# If we are in an interactive session, tie up/down arrow keys to command history.
if [[ $- =~ i ]]; then
    bind '"\e[A": history-search-backward'
    bind '"\e[B": history-search-forward'
    bind '"\e0A": history-search-backward'
    bind '"\e0B": history-search-forward'
fi

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
if [ -f ~/.fzf.bash ]; then
    source ~/.fzf.bash
fi


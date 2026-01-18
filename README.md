# dotfiles: Configuration Files for Terminal Applications

This repository includes the configuration files I use for terminal applications like `VIM`, `tmux` and others.

## Fonts and Icons

In order to use the VIM plug-in [`vim-devicons`](https://github.com/ryanoasis/vim-devicons) and avoid icon/font display issues while decorating the tmux status bar, one needs to install [`Nerd Fonts`](https://github.com/ryanoasis/nerd-fonts). For macOS users, installation via Homebrew is simple:
```
brew tap homebrew/cask-fonts
brew install font-hack-nerd-font
```
Linux users should consult the Nerd Fonts repository for installation details.

## iTerm2 Notes

I use a fairly simple iTerm2 profile that re-defines some useful key mappings from Mac's own _Terminal.app_. It also makes _Hack Regular Nerd Font_ (see above) the default terminal font.

## Common Terminal Utilities

I use the `lsd` utility instead of the default one. For macOS users, installation via Homebrew is as follows:
```
brew install lsd
```

## Python

I use a virtual environment, `pyenv`, to manage Python versions and packages and avoid cluttering system Python installations. To set up the virtual environment, use
```
python3 -m venv ~/pyenv
```
Do not forget to upgrade the virtual environment after upgrading Python:
```
python3 -m venv --upgrade ~/pyenv
```

## VIM Notes

### Plug-in Management

I use [`vim-plug`](https://github.com/junegunn/vim-plug) for managing VIM plug-ins. The `.vimrc` file should take care of bootstrapping `vim-plug` if it isn't there already. However, if you run into issues you can manually set it up via:
```
curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
```
If `vim-plug` is installed manually, you will also need to issue the VIM command `:PlugUpdate` manually to fetch and install the actual plug-ins.

### Ctags

Be aware that macOS does not ship with a [`vim-gutentags`](https://github.com/ludovicchabant/vim-gutentags) compatible `ctags` binary. To use `vim-gutentags` on macOS, one needs to install [Ctags](http://ctags.sourceforge.net/) through Homebrew.

### LSP-Based Code Completion and Syntax Checking via ALE

Out of the box, [`ALE`](https://github.com/w0rp/ale) tries to auto-detect and enable as many tools as it can, so one does not need to do extra configuration. For Python, I recommend [`pyls`](https://github.com/palantir/python-language-server) and my `.vimrc` chooses it as the sole Python tool if the executable `pyls` is in `${PATH}`. As of this writing, I couldn't get [`clangd`](https://clang.llvm.org/extra/clangd.html) to work in `ALE`, so my `.vimrc` defaults to `clang` or `gcc` for linting. Syntax checking does not yet work in C/C++.

### FZF

I generally use [`FZF`](https://github.com/junegunn/fzf.vim) for searching. I also use [`ag`](https://github.com/ggreer/the_silver_searcher), which the FZF plug-in also supports. Fellow macOS users can use Homebrew to install `ag` via:
```
brew install the_silver_searcher
```

## TMux Notes

I use a custom script (`scripts/tmux-select-pane`) to facilitate seamless movements between TMux and VIM panes.

## Claude

I use the scripts `scripts/claude-sandbox` to limit Claude with read/write access to the current directory and read-only access to the necessary system directories (more below). The command `claude` is an alias to run Claude with this sandboxing. See [this repository](https://github.com/neko-kai/claude-code-sandbox) for more details. Mind the following:
- This is macOS-specific, and Linux will require a different approach.
- We *do not* use Claude's built-in sandboxing (see `settings.json`) since it is too permissive.
- There was a bug in the upstream `sandbox-exec` utility due to macOS's `realpath` not supporting the `-m` flag, so I changed the line
  ```
  TARGET_DIR="$(realpath -m "${TARGET_DIR}" 2>/dev/null)"
  ```
  to
  ```
  TARGET_DIR="$(cd "${TARGET_DIR}" 2>/dev/null && pwd -P || echo "${TARGET_DIR}")"
  ```
- I gave access to certain standard "files" (e.g., `/dev/stdin`) the upstream code doesn't. This is necessary for things like Python's `subprocess` module to work properly. Find these additions by searching for the comment `;; Missing from upstream`.

### Permissions/Access Model

This setup consists of three layers:
- The primary security boundary is an OS-level macOS sandbox (`sandbox-exec`) that restricts file reads to the current working directory and system paths, limits writes to the project directory, `/tmp`, and select caches (`~/.cache`, `~/.claude`), while permitting full network access.
- A pre-execution hook (`path_check.py`) provides friendly error messages when commands reference paths outside the sandbox boundaries, catching many mistakes before they hit the OS sandbox.
- The permissions layer in `settings.json` controls prompting UX rather than security: it auto-approves ~200 common development commands (coreutils, git, build tools, compilers, linters, network utilities) for seamless workflow, requires confirmation for operations affecting remote systems (`git push`, package publishing, `docker`, GitHub write operations), and outright blocks dangerous patterns (`sudo`/`su`, force push, repository deletion) and sensitive file reads (.env, secrets,
  credentials).

The aim is to prioritize development productivity by eliminating prompts for safe local operations while maintaining human oversight for irreversible or remote-affecting actions, with the OS sandbox as the ultimate safety net.


# dotfiles: Configuration Files for Terminal Applications

This repository includes the configuration files I use for terminal applications like `VIM`, `tmux` and others.

## Fonts and Icons

To be able to use the VIM plug-in [`vim-devicons`](https://github.com/ryanoasis/vim-devicons) and avoid icon/font display issues while decorating the tmux status bar, one needs to install [`Nerd Fonts`](https://github.com/ryanoasis/nerd-fonts). For macOS users, installation via Homebrew is simple:
```
brew tap caskroom/fonts
brew cask install font-hack-nerd-font
```
Linux users should consult the Nerd Fonts repository for installation details.

## VIM Notes

### Ctags

Be aware that macOS does not ship with a [`vim-gutentags`](https://github.com/ludovicchabant/vim-gutentags) compatible `ctags` binary. To use `vim-gutentags` on macOS, one needs to install [Ctags](http://ctags.sourceforge.net/) through Homebrew.

### LSP-Based Code Completion and Syntax Checking via ALE

Out of the box, [`ALE`](https://github.com/w0rp/ale) tries to auto-detect and enable as many tools as it can, so one does not need to do extra configuration. For Python, I recommend [`pyls`](https://github.com/palantir/python-language-server) and my `.vimrc` chooses it as the sole Python tool if the executable `pyls` is in `${PATH}`. As of this writing, I couldn't get [`clangd`](https://clang.llvm.org/extra/clangd.html) to work in `ALE`, so my `.vimrc` defaults to `clang` or `gcc` for linting. Syntax checking does not yet work in C/C++.

### Denite

I use [`denite`](https://github.com/Shougo/denite.nvim) for searching. My set-up tries using [`ag`](https://github.com/ggreer/the_silver_searcher) if it is in `${PATH}`, and defaults to `grep` otherwise. Fellow macOS users can use Homebrew to install `ag` via:
```
brew install the_silver_searcher
```

## TMux Notes

I use a custom script (`scripts/tmux-select-pane`) to facilitate seamless movements between TMux and VIM panes.

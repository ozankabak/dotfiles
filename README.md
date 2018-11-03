# dotfiles
Configuration (DOT) Files for Terminal Applications

This repository includes the configuration files I use for terminal applications like `VIM`, `tmux` and others.

## VIM Notes

### Icons

To be able to use the plug-in [`vim-devicons`](https://github.com/ryanoasis/vim-devicons) and avoid icon display issues, one needs to install [`Nerd Fonts`](https://github.com/ryanoasis/nerd-fonts). For macOS users, installation via Homebrew is simple:
```
brew tap caskroom/fonts
brew cask install font-hack-nerd-font
```
Linux users should consult the Nerd Fonts repository for installation details.

### Ctags

Be aware that macOS does not ship with a [`vim-easytags`](https://github.com/xolox/vim-easytags) compatible `ctags` binary. This `.vimrc` suppresses the warning emitted by the plug-in about this issue. To use `vim-easytags` on macOS, one needs to install [Exuberant Ctags](http://ctags.sourceforge.net/) through Homebrew.

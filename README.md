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

## Agent Sandboxing

I use `scripts/agent-sandbox` to limit Claude and Codex with read/write access to the current directory and read-only access to the necessary system directories (more below). The `claude` and `codex` aliases run their respective agent through this sandbox. See [this repository](https://github.com/neko-kai/claude-code-sandbox) for more details. Mind the following:

- This is macOS-specific, and Linux will require a different approach.
- We do not rely on the agent's own sandbox: Claude disables its built-in sandbox, while Codex runs with `--sandbox danger-full-access`. The outer macOS sandbox remains the enforcing boundary because macOS does not support nesting `sandbox-exec` profiles.

### Permissions/Access Model

This setup consists of three layers:

- The primary security boundary is an OS-level macOS sandbox (`sandbox-exec`) that restricts file reads to the current working directory and system paths, limits writes to the project directory, `/tmp`, select caches, and the agent's state directory (`~/.claude` or `~/.codex`), while permitting full network access.
- A pre-execution hook (`path_check.py`) provides friendly error messages when commands reference paths outside sandbox boundaries, catching many mistakes before they hit the OS sandbox. This hook also rejects shell access to workspace `.env`/`.env.*`, `*.pem`, `*.key`, `id_rsa*`, `.ssh`, `.aws`, and `.gnupg` paths. The outer `agent-sandbox` profile also denies reads for these patterns.
- The hook mirrors the tiers of the sandbox profile rather than applying a stricter policy of its own. Because the profile grants every agent state directory unconditionally, either agent may read and repair the other's configuration. Redirect targets (`>`, `>>`, `2>`, `<>`, …) are the one case where the hook can prove write intent, so it checks those against the writable tier only; writes it cannot prove, such as `cp ./a /usr/local/x`, it defers to the OS sandbox.
- The overlay carves credential and identity stores out of the readable system roots: `/etc/sudoers`, `/etc/sudoers.d`, `/etc/master.passwd`, `/etc/krb5.keytab`, `/etc/ssh`, `/etc/ssl/private`, and the OpenDirectory records under `/var/db/dslocal`. No agent tooling reads these, so the denies cost nothing; neighbouring paths such as `/etc/ssl/cert.pem` stay readable. The hook mirrors them.
- The hook classifies arguments per command; so scripts, regexes and non-path flag values are not mistaken for paths: `sed '/pattern/d'`, `awk '/pattern/ {print}'`, `grep -E '/[a-z]+/'` and `cut -d/` do not trip it. Commands outside its table keep the conservative default of treating every argument containing a `/` as a path, so an incomplete table degrades to extra prompts rather than to a gap.
- The hook always checks operands, redirect targets and the command name itself, along with a here-document's command line. It treats the body as the data it is, so a path appearing in a commit message written that way is not a file access. However, it still scans a body with an unquoted delimiter for command substitution because the shell expands those.
- Anything that merely introduces a command goes through the same mechanism, so the real command keeps its own rules: wrappers (`env`, `nice`, `xargs`, `timeout`, including their options and any positional argument they spend first), shell keywords (`if`, `do`, `else`, `!`), and subcommand runners (`git`). Brace groups, function bodies, process substitutions and `find -exec` likewise start a command line of their own.
- If the hook itself fails, it refuses the command and names the exception, rather than letting the failure read as approval. This matters because the two agents interpret an empty response differently: Codex treats silence as permission, Claude does not, so an unhandled error would otherwise disable the check for one agent and block the other.
- `scripts/check-policy-sync.py` fails if the profile grants a path the hook's tables do not cover. It also fails if the hook refuses a path the profile permits, so the hook cannot invent restrictions of its own. Because profiles are last-match-wins and the base profile denies `/` before re-allowing individual trees, that second check evaluates the effective verdict for a path rather than looking for any deny. It runs as part of `scripts/test-agent-sandbox.sh`, so adding a rule to the overlay without teaching the hook about it is caught by the test suite rather than by a puzzling rejection later.
- The `agent-sandbox` script gives read-only Keychain access so Claude retrieves its API key, Codex validates the local certificate issuer, and GitHub CLI retrieves its OAuth token.
- Run `scripts/test-agent-sandbox.sh --agent claude` or `scripts/test-agent-sandbox.sh --agent codex` from the host (not an existing `sandbox-exec` session) to verify the effective profile.
- Claude's `settings.json` and Codex's `.codex/rules/default.rules` control command prompting rather than filesystem security. They auto-approve common development commands, require confirmation for remote-affecting operations, and block dangerous command patterns such as `sudo`, force pushes, and repository deletion. Claude also blocks sensitive-file reads; Codex applies those path protections through its hook and the sandbox.

The aim is to prioritize development productivity by eliminating prompts for safe local operations while maintaining human oversight for irreversible or remote-affecting actions, with the OS sandbox as the ultimate safety net.

### Codex

- The `scripts/generate-codex-rules.py` script generates `.codex/rules/default.rules` from Claude's Bash permissions. When changing `.claude/settings.json`, regenerate the rules and review the two files together. Generated rules preserve `allow`, `prompt`, and `forbidden` decisions through Codex's native execution-policy engine. Note that Codex's execution-policy rules cannot represent Claude's `Read` and `Edit` permissions, so Codex relies on `path_check.py` and the `agent-sandbox` script to enforce sensitive-file checks.
- The generator prints every non-Bash Claude permission it omits, with the count in each category heading, so review its output whenever `.claude/settings.json` changes.
- Codex does not provide an executable custom status-line hook.

### Agent Instructions

[INSTRUCTIONS.md.j2](INSTRUCTIONS.md.j2) is the single source of truth for `.claude/CLAUDE.md` and `.codex/AGENTS.md`. After editing it, run `scripts/render-agent-instructions.py` to regenerate them and commit the outputs.

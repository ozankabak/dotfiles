#!/bin/bash
# Comprehensive test suite for path_check.py.
# Run: ./test_path_check.sh --agent <claude|codex>

AGENT=""
if [[ "${1:-}" == "--agent" ]]; then
    AGENT="$2"
    shift 2
fi
if [[ "$AGENT" != "claude" && "$AGENT" != "codex" ]]; then
    echo "Usage: $0 [--agent <claude|codex>]" >&2
    exit 1
fi
# Resolve both defaults from this script's own location, as
# scripts/test-agent-sandbox.sh does. A checkout then tests itself rather than
# whatever exists in $HOME, and the notional project root stays the same.
HOOK="${HOOK:-$(cd "$(dirname "$0")" && pwd -P)/path_check.py}"
CWD="${CWD:-$(cd "$(dirname "$0")/.." && pwd -P)}"
# For env var expansion tests. Deliberately a variable the hook's policy knows
# nothing about: $HOME and $TMPDIR are baked into its tables, so they cannot show
# that expansion is generic rather than special-cased.
export EVIL="/Users/nobody"
# Parser tests use /Users/nobody/outside* as the "outside the sandbox" sentinel.
# We use a literal rather than a variable because many parser cases embed the
# sentinel in strings with single quotes where shell expansion does not happen,
# and _extract_paths only treats tokens containing "/" as path candidates.
if [[ "$AGENT" == "claude" ]]; then
    export CLAUDE_PROJECT_DIR="$CWD"
else
    export CODEX_PROJECT_DIR="$CWD"
fi
PASS=0
FAIL=0

test_cmd() {
    local expected="$1" desc="$2" cmd="$3"
    # Use jq to properly escape the command for JSON
    local input output decision
    input=$(jq -n --arg cmd "$cmd" --arg cwd "$CWD" '{"tool_input":{"command":$cmd},"cwd":$cwd}')
    output=$(echo "$input" | python3 "$HOOK" --agent "$AGENT" 2>/dev/null)
    if [[ "$AGENT" == "claude" ]]; then
        decision=$(echo "$output" | jq -r '.decision // "error"')
        expected_decision="approve"
        if [[ "$decision" == "$expected_decision" ]]; then
            result=0
        else
            result=2
        fi
    elif [[ "$expected" -eq 0 ]]; then
        if [[ -z "$output" ]]; then
            result=0
        else
            result=2
        fi
    else
        decision=$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision // "error"')
        if [[ "$decision" == "deny" ]]; then
            result=2
        else
            result=0
        fi
    fi
    if [[ "$result" -eq "$expected" ]]; then
        echo "✓ $desc"
        ((PASS++))
    else
        echo "✗ $desc"
        echo "  cmd: $cmd"
        echo "  expected: $expected, got: $result ($output)"
        ((FAIL++))
    fi
}

echo "=== Basic Paths ==="
test_cmd 2 "parent traversal" "cat ../../../Users/nobody/outside"
test_cmd 2 "/var/tmp write refused" "echo test > /var/tmp/file"
test_cmd 0 "CWD relative" "cat ./file.txt"
test_cmd 0 "CWD nested" "cat ./dir/subdir/file.txt"
test_cmd 0 "CWD implicit (no slash)" "cat file.txt"
test_cmd 0 "/tmp absolute" "touch /tmp/test"
test_cmd 0 "/tmp nested" "cat /tmp/foo/bar/baz"
test_cmd 0 "/private/tmp (macOS)" "touch /private/tmp/file"
test_cmd 0 "system read /etc" "cat /etc/hosts"
test_cmd 0 "system read /var" "ls /var/log"
test_cmd 0 "system read /opt" "cat /opt/file"
test_cmd 0 "root directory listing" "ls /"
test_cmd 0 "/var/tmp read allowed" "cat /var/tmp/file"

echo ""
echo "=== Tilde Expansion ==="
test_cmd 2 "tilde home outside" "cat ~/.bashrc"
test_cmd 2 "tilde in flag" "cmd --config=~/.config/app"
test_cmd 2 "tilde ssh" "cat ~/.ssh/id_rsa"
test_cmd 2 "tilde redirect" "echo test > ~/output.txt"
test_cmd 0 "tilde .cache allowed" "ls ~/.cache"

echo ""
echo "=== Agent State Exception ==="
AGENT_HOME="$HOME/.${AGENT}"
test_cmd 0 "agent home allowed" "ls $AGENT_HOME"
test_cmd 0 "agent home subdir" "cat $AGENT_HOME/config.toml"
test_cmd 0 "agent home nested" "ls $AGENT_HOME/hooks/path_check.py"
test_cmd 0 "agent home redirect" "echo test > $AGENT_HOME/test.txt"
test_cmd 0 "agent home in flag" "cmd --config=$AGENT_HOME/config"
test_cmd 0 "agent home via HOME" "ls \$HOME/.${AGENT}"
# The profile grants every agent home unconditionally, so either agent may repair
# the other's configuration.
OTHER_AGENT=$([[ "$AGENT" == "claude" ]] && echo codex || echo claude)
test_cmd 0 "other agent home allowed" "ls $HOME/.${OTHER_AGENT}"
test_cmd 0 "other agent home write" "echo test > $HOME/.${OTHER_AGENT}/test.txt"
test_cmd 0 "claude.json allowed" "cat ~/.claude.json"

echo ""
echo "=== Shared Tool State ==="
test_cmd 2 "unrelated config blocked" "cat ~/.config/other/app.conf"
test_cmd 2 "home file read" "cat ~/.bash_history"
test_cmd 0 "hook directory" "ls ~/.agent-hooks"
test_cmd 0 "cargo home" "ls ~/.cargo/registry"
test_cmd 0 "elan toolchains" "ls ~/.elan"
test_cmd 0 "uv managed pythons" "ls ~/.local/share/uv"
test_cmd 0 "lima cache" "ls ~/Library/Caches/lima"
test_cmd 0 "git config" "cat ~/.gitconfig"
test_cmd 0 "gh config" "cat ~/.config/gh/hosts.yml"
# Parent directories of the project root are listable but not readable, matching
# the literal rules agent-sandbox generates for them.
test_cmd 0 "home listing" "ls ~"

echo ""
echo "=== Sensitive Workspace Paths ==="
test_cmd 2 "workspace .env blocked" "cat .env"
test_cmd 2 "workspace .env variant blocked" "cat ./config/.env.local"
test_cmd 2 "workspace PEM blocked" "cat ./config/service.pem"
test_cmd 2 "workspace key blocked" "cat ./config/service.key"
test_cmd 2 "workspace SSH key blocked" "cat ./config/id_rsa_backup"
test_cmd 2 "workspace .ssh blocked" "cat ./.ssh/id_ed25519"
test_cmd 2 "workspace .aws blocked" "cat ./.aws/credentials"
test_cmd 2 "workspace .gnupg blocked" "cat ./.gnupg/private-keys-v1.d/key"
# A leading dash does not exempt a sensitive name from the check.
test_cmd 2 "dash-prefixed PEM blocked" "cat -.pem"
test_cmd 2 "dash-prefixed key blocked" "cat -.key"
test_cmd 0 "ordinary workspace file allowed" "cat ./config/application.toml"

echo ""
echo "=== System Credential Stores ==="
# Carved out of the readable system roots by the overlay's deny rules.
test_cmd 2 "sudoers blocked" "cat /etc/sudoers"
test_cmd 2 "sudoers.d blocked" "ls /etc/sudoers.d"
test_cmd 2 "master.passwd blocked" "cat /etc/master.passwd"
test_cmd 2 "krb5 keytab blocked" "cat /etc/krb5.keytab"
test_cmd 2 "ssh host keys blocked" "cat /etc/ssh/ssh_host_rsa_key"
test_cmd 2 "private TLS keys blocked" "ls /etc/ssl/private"
test_cmd 2 "directory services blocked" "ls /var/db/dslocal"
test_cmd 2 "directory services via /private" "ls /private/var/db/dslocal"
# The denies are surgical: their neighbours under the same roots stay readable.
test_cmd 0 "CA bundle still allowed" "cat /etc/ssl/cert.pem"
test_cmd 0 "system hosts file still allowed" "cat /etc/hosts"

echo ""
echo "=== Command Argument Classification ==="
# Scripts, patterns and non-path flag values are not paths, but the operands and
# the command name around them still are.
test_cmd 2 "sed script then outside file" "sed 's/a/b/' /Users/nobody/outside"
test_cmd 2 "awk program then outside file" "awk '{print}' /Users/nobody/outside"
test_cmd 2 "grep pattern then outside file" "grep pattern /Users/nobody/outside"
test_cmd 2 "sed -f outside script" "sed -f /Users/nobody/outside ./file"
test_cmd 2 "awk -f outside script" "awk -f /Users/nobody/outside ./data"
test_cmd 2 "outside command name" "/Users/nobody/outside --help"
test_cmd 2 "outside command via wrapper" "env FOO=bar /Users/nobody/outside"
test_cmd 2 "outside path after separator" "ls ./a; /Users/nobody/outside"
test_cmd 2 "perl script then outside file" "perl -pe 's/a/b/' /Users/nobody/outside"
test_cmd 2 "attached long script flag" "sed --expression='s/a/b/' /Users/nobody/outside"
test_cmd 2 "attached long path flag" "sed --file=/Users/nobody/outside ./x"
test_cmd 2 "outside file after pipe" "cat ./a | grep pattern /Users/nobody/outside"
test_cmd 2 "outside file inside subshell" "(cd ./x && sed 's/a/b/' /Users/nobody/outside)"
# A script supplied by flag frees the first operand to be an ordinary path.
test_cmd 0 "sed -e frees the operand" "sed -e 's/a/b/' ./file"
test_cmd 0 "grep -e frees the operand" "grep -e pattern ./file"
test_cmd 0 "find name pattern" "find . -name '/etc/*'"
test_cmd 0 "sort field separator" "sort -t/ -k2 ./file"
test_cmd 0 "jq filter" "jq '.a/.b' ./file.json"
test_cmd 0 "unknown command keeps checking" "mycmd ./file"
test_cmd 0 "sed line range" "sed -n '1,10p' ./file"
test_cmd 0 "awk arithmetic in program" "awk 'BEGIN{print 1/2}' ./file"
test_cmd 0 "grep counting slashes" "grep -c '/' ./file"
test_cmd 0 "jq object path" "jq -r '.a.b' ./file"
test_cmd 0 "rg with long flag" "rg --json 'x/y' ./src"
test_cmd 0 "wrapper with no command" "timeout 5"
# A wrapper's own options must not be mistaken for the command it runs, which
# would prevent applying the inner command's rules.
test_cmd 2 "wrapper option then outside file" "nice -n 10 sed 's/a/b/' /Users/nobody/outside"
test_cmd 2 "wrapper path option is checked" "env -C /Users/nobody/outside ls"
test_cmd 2 "xargs replace then outside file" "xargs -I{} sed 's/a/b/' /Users/nobody/outside"
test_cmd 0 "nice option then sed script" "nice -n 10 sed '/pattern/d' ./file"
test_cmd 0 "stdbuf attached option then grep" "stdbuf -o0 grep -E '/[a-z]+/' ./file"
test_cmd 0 "env unset then sed script" "env -u FOO sed '/pattern/d' ./file"
test_cmd 0 "xargs replace then awk program" "xargs -I{} awk '/pattern/ {print}' ./file"
test_cmd 0 "stacked wrappers" "nohup nice -n 5 sed '/x/d' ./file"
# Wrappers that spend a positional argument before naming their command.
test_cmd 2 "timeout then outside file" "timeout 5 cat /Users/nobody/outside"
test_cmd 2 "timeout then outside redirect" "timeout 5 cat > /Users/nobody/outside"
test_cmd 2 "flock outside lock file" "flock /Users/nobody/outside sed 's/a/b/' ./f"
test_cmd 2 "xargs arg-file is checked" "xargs -a /Users/nobody/outside grep x"
test_cmd 0 "timeout duration then sed script" "timeout 5 sed '/pattern/d' ./file"
test_cmd 0 "timeout flag and duration" "timeout -k 1 5 awk '/x/ {print}' ./file"
test_cmd 0 "flock lock file then grep" "flock ./lock grep -E '/[a-z]+/' ./file"
# A quoted separator resets command position, which must not skip the next path.
test_cmd 2 "quoted separator then outside" "grep '&&' /Users/nobody/outside"
# An empty argument is not an operand; the BSD `sed -i` idiom must not consume the
# script role and turn the script into a path.
test_cmd 2 "BSD sed -i then outside file" "sed -i '' 's/a/b/' /Users/nobody/outside"
test_cmd 0 "BSD sed -i empty suffix" "sed -i '' '/pattern/d' ./file"
# After --, an argument is an operand even when it looks like a flag.
test_cmd 2 "end of options then outside" "grep -- -x /Users/nobody/outside"
test_cmd 0 "end of options then file" "grep -- -x ./file"
# Substitutions execute even inside an argument the classifier skips.
test_cmd 2 "substitution inside sed script" "sed \"s/\$(cat /Users/nobody/outside)/x/\" ./f"
test_cmd 2 "substitution inside grep pattern" "grep \"\$(cat /Users/nobody/outside)\" ./f"
test_cmd 2 "find -exec outside argument" "find . -exec cat /Users/nobody/outside ;"
test_cmd 0 "find -exec placeholder" "find . -exec cat {} ;"

echo ""
echo "=== Shell Keywords and Grouping ==="
# A keyword introduces a command rather than being one, so the command that
# follows must keep its own argument rules.
test_cmd 0 "command after if" "if grep -E '/[a-z]+/' ./f; then echo hi; fi"
test_cmd 0 "command after do" "for f in ./*.py; do sed '/x/d' \$f; done"
test_cmd 0 "command in a while body" "while read l; do awk '/x/ {print}' ./f; done"
test_cmd 0 "command after negation" "if ! grep -E '/x/' ./f; then echo no; fi"
test_cmd 0 "command after else" "if true; then :; else sed '/x/d' ./f; fi"
test_cmd 0 "command after until" "until sed '/x/d' ./f; do echo retry; done"
test_cmd 0 "command in a brace group" "{ sed '/x/d' ./f; }"
test_cmd 0 "command in a case branch" "case \$x in a) sed '/y/d' ./f;; esac"
test_cmd 0 "wrapper inside a loop body" "for f in ./*; do timeout 5 sed '/x/d' \$f; done"
# Keywords must not hide an outside path either.
test_cmd 2 "outside path after then" "if grep -q x ./f; then cat /Users/nobody/outside; fi"
test_cmd 2 "outside path in a loop body" "for f in ./*.py; do sed 's/a/b/' /Users/nobody/outside; done"
test_cmd 2 "outside path in a brace group" "{ cat /Users/nobody/outside; }"
test_cmd 2 "outside path after negation" "if ! cat /Users/nobody/outside; then echo no; fi"

echo ""
echo "=== Command Position Re-entry ==="
# Function bodies, brace groups, process substitutions and `find -exec` all start
# a command line of their own, so the command inside keeps its own rules.
test_cmd 2 "outside path in a function body" "function foo { cat /Users/nobody/outside; }"
test_cmd 2 "outside path in process substitution" "diff <(sed 's/a/b/' /Users/nobody/outside) ./b"
test_cmd 2 "outside path after find -exec" "find . -exec cat /Users/nobody/outside ;"
test_cmd 2 "wrapper after find -exec with outside path" "find . -exec timeout 5 cat /Users/nobody/outside ;"
test_cmd 2 "second find -exec clause outside" "find . -exec grep -l x {} ; -exec cat /Users/nobody/outside ;"
test_cmd 2 "outside path in redirected substitution" "cmd > >(sed 's/a/b/' /Users/nobody/outside)"
test_cmd 0 "function definition body" "function foo { sed '/x/d' ./f; }"
test_cmd 0 "function shorthand body" "foo() { grep -E '/[a-z]+/' ./f; }"
test_cmd 0 "process substitution inputs" "diff <(sed '/x/d' ./a) <(sed '/y/d' ./b)"
test_cmd 0 "process substitution output" "tee >(grep -E '/x/' > ./log) < ./in"
test_cmd 0 "find -exec keeps grep rules" "find . -type f -exec grep -E '/x/' {} ;"
test_cmd 0 "find -exec with sed placeholder" "find . -exec sed -i '' 's/a/b/' {} +"
test_cmd 0 "heredoc inside process substitution" $'diff <(cat <<\'EOF\'\n/Users/nobody/outside\nEOF\n) ./b'
test_cmd 0 "find -exec carrying a wrapper" "find . -exec timeout 5 sed '/x/d' {} ;"
test_cmd 0 "two find -exec clauses" "find . -exec grep -l x {} ; -exec sed -i '' 's/a/b/' {} ;"
test_cmd 0 "xargs replacing into sed" "find . -print0 | xargs -0 -I{} sed -i '' 's/a/b/' {}"
test_cmd 0 "redirect into process substitution" "cmd > >(sed '/x/d' > ./log)"
# A command produced by substitution cannot be resolved, so its arguments fall back
# to the conservative default. Blocking here is the safe side of an unavoidable gap.
test_cmd 2 "script argument after substitution (known limit)" "\$(which sed) '/x/d' ./f"
test_cmd 2 "script argument after backticks (known limit)" "\`which sed\` '/x/d' ./f"
test_cmd 2 "outside path after substitution" "\$(which cat) /Users/nobody/outside"

echo ""
echo "=== Grouping, Pipelines and Assignments ==="
test_cmd 2 "outside path in backgrounded group" "{ cat /Users/nobody/outside; } &"
test_cmd 2 "outside path in a while body" "while [[ -f ./f ]]; do cat /Users/nobody/outside; done"
test_cmd 2 "assignment then outside path" "PATH=./bin:\$PATH cat /Users/nobody/outside"
test_cmd 0 "backgrounded brace group" "{ sed '/x/d' ./f; } &"
test_cmd 0 "timed pipeline" "time sed '/x/d' ./f | grep x"
test_cmd 0 "negated pipeline" "! sed '/x/d' ./f | grep x"
test_cmd 0 "while with a bracket test" "while [[ -f ./f ]]; do sed '/x/d' ./f; done"
test_cmd 0 "assignment before a spec'd command" "PATH=./bin:\$PATH sed '/x/d' ./f"
test_cmd 0 "env -i before a spec'd command" "env -i sed '/x/d' ./f"

echo ""
echo "=== Line Continuations ==="
# A backslash continuation leaves a bare newline token that is not an argument.
test_cmd 2 "continuation before an outside path" $'cd ./x && \\\n  cat /Users/nobody/outside'
test_cmd 2 "continuation before an outside redirect" $'sed \'/x/d\' ./f \\\n  > /Users/nobody/outside'
test_cmd 0 "continuation before a command" $'cd ./x && \\\n  sed \'/y/d\' ./f'
test_cmd 0 "continuation before a redirect" $'sed \'/x/d\' ./f \\\n  > ./out'

echo ""
echo "=== Nested Wrappers and Keywords ==="
test_cmd 2 "wrapper chain then outside path" "timeout 5 env FOO=1 sed 's/a/b/' /Users/nobody/outside"
test_cmd 2 "stacked wrappers then outside path" "nohup timeout 5 nice -n 10 cat /Users/nobody/outside"
test_cmd 0 "wrapper chain keeps sed rules" "timeout 5 env FOO=1 sed '/x/d' ./f"
test_cmd 0 "keyword then wrapper chain" "for f in ./*; do timeout 5 flock ./lock sed '/x/d' \$f; done"
test_cmd 0 "keyword then xargs then git" "if xargs -I{} git grep -E '/x/' ./f; then echo hi; fi"
test_cmd 0 "three stacked wrappers" "nohup timeout 5 nice -n 10 sed '/x/d' ./f"

echo ""
echo "=== Subcommand Runners ==="
test_cmd 2 "git -C outside" "git -C /Users/nobody/outside status"
test_cmd 2 "git add outside" "git add /Users/nobody/outside"
test_cmd 2 "git grep pathspec outside" "git grep pattern -- /Users/nobody/outside"
test_cmd 2 "git log pathspec outside" "git log -- /Users/nobody/outside"
test_cmd 2 "git grep end of options outside" "git grep -- -x /Users/nobody/outside"
test_cmd 0 "git grep keeps grep rules" "git grep -E '/[a-z]+/' -- ./src"
test_cmd 0 "git -C with workspace path" "git -C ./sub status"
test_cmd 0 "git commit message with slashes" "git commit -m 'fix /a/b handling'"
test_cmd 0 "git log pathspec" "git log -- ./path"
test_cmd 0 "git grep after end of options" "git grep -- -x ./f"
test_cmd 0 "git diff pathspec" "git diff --stat -- ./src"

echo ""
echo "=== Here-Documents ==="
# A here-document body is text the command reads on standard input, not a list of
# arguments, so absolute paths inside it are data.
test_cmd 0 "quoted heredoc body is data" $'cat > ./f <<\'EOF\'\n/Users/nobody/outside\nEOF'
test_cmd 0 "unquoted heredoc body is data" $'cat > ./f <<EOF\nprefix /Users/nobody/outside\nEOF'
test_cmd 0 "indented heredoc body is data" $'cat > ./f <<-EOF\n/Users/nobody/outside\nEOF'
test_cmd 0 "heredoc feeding a commit message" $'git commit -F - <<\'MSG\'\nsee /Users/nobody/outside\nMSG'
# A quoted delimiter suppresses substitution; an unquoted one does not.
test_cmd 2 "unquoted heredoc expands substitution" $'cat > ./f <<EOF\n$(cat /Users/nobody/outside)\nEOF'
test_cmd 0 "quoted heredoc suppresses substitution" $'cat > ./f <<\'EOF\'\n$(cat /Users/nobody/outside)\nEOF'
# Hook still checks the command line introducing the heredoc.
test_cmd 2 "heredoc redirect target checked" $'cat > /Users/nobody/outside <<\'EOF\'\ntext\nEOF'
test_cmd 2 "operand beside a heredoc checked" $'cat /Users/nobody/outside <<\'EOF\'\ntext\nEOF'
test_cmd 0 "here-string is not a heredoc" "cat <<< 'text'"

echo ""
echo "=== Conditionals and Descriptors ==="
test_cmd 2 "test on an outside file" "test -f /Users/nobody/outside"
test_cmd 2 "bracket test on an outside file" "[[ -f /Users/nobody/outside ]] && echo yes"
test_cmd 2 "descriptor read from outside" "exec 3< /Users/nobody/outside"
test_cmd 2 "expanded home file" "echo \${HOME}/.bashrc"
test_cmd 0 "test on a system file" "[[ -f /etc/hosts ]] && echo yes"
test_cmd 0 "test on a workspace file" "test -f ./f && echo yes"
test_cmd 0 "descriptor duplication" "cmd >/dev/null 2>&1"
test_cmd 0 "descriptor read from workspace" "exec 3< ./f"
test_cmd 0 "parameter expansion of PATH" "echo \${PATH}"
test_cmd 0 "parameter default value" "echo \${x:-./default}"

echo ""
echo "=== Values That Merely Look Like Paths ==="
test_cmd 0 "arithmetic expansion" "echo \$((10/2))"
test_cmd 0 "nested arithmetic division" "echo \$((a/b+c/d))"
test_cmd 0 "classpath colon list" "java -cp /usr/share/a.jar:/usr/share/b.jar Main"
test_cmd 0 "URL argument" "curl -sS https://example.com/a/b -o ./out"
test_cmd 0 "git remote address" "git remote add origin git@github.com:user/repo.git"
test_cmd 0 "date format string" "date +%Y/%m/%d"
test_cmd 0 "log format string" "git log --format=%H/%s"
test_cmd 0 "paste delimiter" "paste -d/ ./a ./b"
test_cmd 0 "awk field separator slash" "awk -F/ '{print \$2}' ./f"
test_cmd 0 "sed in-place with suffix" "sed -i.bak 's/a/b/' ./f"
test_cmd 0 "sed alternate delimiters twice" "sed -e 's|/a|/b|' -e '/x/d' ./f"
test_cmd 0 "loop over a glob" "for f in ./*.py; do cat \$f; done"
test_cmd 0 "brace expansion" "cp ./{a,b} ./dst"
test_cmd 0 "remote command in quotes" "ssh host 'ls /etc'"
test_cmd 0 "pytest module invocation" "python3 -m pytest -q ./tests"
# The same commands still refuse a real outside path.
test_cmd 2 "sort output file" "sort -o /Users/nobody/outside ./f"
test_cmd 2 "sort attached output file" "sort -o/Users/nobody/outside ./f"
test_cmd 2 "find newer reference file" "find . -newer /Users/nobody/outside"
test_cmd 2 "classpath entry outside" "java -cp /Users/nobody/outside Main"
test_cmd 2 "outside path inside a loop" "for f in ./*.py; do cat /Users/nobody/outside; done"

echo ""
echo "=== Quoting and Normalization ==="
test_cmd 2 "concatenated quoted parts" 'cat "/Users""/nobody/outside"'
test_cmd 2 "partially quoted path" 'cat /Users/nobody/out"side"'
test_cmd 2 "backslash escape in path" "cat /Users/nobody/out\\side"
test_cmd 2 "traversal through /tmp" "cat /tmp/../Users/nobody/outside"
test_cmd 2 "traversal out of a cache" "cat ~/.cache/../.ssh/id_rsa"
test_cmd 2 "credential store via dot segment" "cat /etc/./sudoers"
test_cmd 2 "credential store via traversal" "cat /etc/../etc/sudoers"
test_cmd 2 "credential store via /private" "cat /private/etc/sudoers"
# Normalization must not over-block: these resolve to permitted paths.
test_cmd 0 "traversal back into a cache" "cat ~/.cache/../.cache/x"
test_cmd 0 "sibling of a denied directory" "cat /etc/ssl/private/../cert.pem"

echo ""
echo "=== Environment Variable Paths ==="
test_cmd 2 "env var outside path" 'cat $EVIL/secret'
test_cmd 2 "env var in redirect" 'echo test > $EVIL/file'
test_cmd 2 "HOME subdir blocked" 'ls $HOME/unknown-subdir'
test_cmd 0 "HOME subdir allowed" 'ls $HOME/.cache'
test_cmd 0 "TMPDIR safe" 'ls $TMPDIR'

echo ""
echo "=== Flags ==="
test_cmd 0 "short flags" "ls -la"
test_cmd 0 "long flags" "grep --recursive pattern"
test_cmd 0 "multiple flags" "ls -la -h --color=auto"
test_cmd 0 "flag with value" "cmd -o output.txt"

echo ""
echo "=== Flag-Embedded Paths ==="
test_cmd 0 "gcc -I system" "gcc -I/usr/include main.c"
test_cmd 0 "--prefix system" "./configure --prefix=/usr/local"
test_cmd 0 "--config system" "cmd --config=/etc/app.conf"
test_cmd 0 "-I to CWD" "gcc -I./include main.c"
test_cmd 0 "--output to /tmp" "cmd --output=/tmp/file"
test_cmd 0 "-o to CWD" "gcc -o ./output main.c"
test_cmd 0 "-L system" "gcc -L/usr/lib main.c"
test_cmd 0 "flag=value no path" "cmd --verbose=true"

echo ""
echo "=== Redirections ==="
test_cmd 2 "stdout > read-only" "echo test > /etc/foo"
test_cmd 2 "stdout >> read-only" "echo test >> /var/log/app.log"
test_cmd 2 "stderr 2> read-only" "cmd 2> /etc/errors"
test_cmd 2 "both &> read-only" "cmd &> /etc/output"
test_cmd 2 "fd >& read-only" "cmd >& /etc/log"
test_cmd 2 "<> read-only" "cmd <>/etc/file"
test_cmd 2 "stdin < outside" "cmd < /Users/nobody/outside"
test_cmd 0 "redirect to CWD" "echo test > ./output.txt"
test_cmd 0 "redirect to /tmp" "echo test > /tmp/output.txt"
test_cmd 0 "<> to /dev/tty" "cmd <>/dev/tty"
test_cmd 0 "stdin < from CWD" "cmd < ./input.txt"
test_cmd 0 "stdin < system read" "cmd < /etc/hosts"

echo ""
echo '=== Command Substitution $() ==='
test_cmd 2 "unsafe \$()" "echo \$(cat /Users/nobody/outside)"
test_cmd 2 "unsafe nested \$()" "echo \$(cat \$(cat /Users/nobody/outside2))"
test_cmd 2 "mixed safe/unsafe \$()" "echo \$(cat ./a) \$(cat /Users/nobody/outside)"
test_cmd 2 "deeply nested unsafe" "echo \$(echo \$(echo \$(cat /Users/nobody/outside)))"
test_cmd 0 "safe nested \$()" "echo \$(cat \$(ls ./))"
test_cmd 0 "safe \$()" "echo \$(cat ./file)"
test_cmd 0 "multiple safe \$()" "echo \$(cat ./a) \$(cat ./b)"

echo ""
echo "=== Process Substitution <() >() ==="
test_cmd 2 "unsafe <()" "diff <(cat /Users/nobody/outside) ./b"
test_cmd 2 "unsafe >()" "tee >(cat > /etc/log)"
test_cmd 2 "nested in <()" "diff <(cat \$(cat /Users/nobody/outside)) ./b"
test_cmd 0 "safe >()" "tee >(cat > ./log)"
test_cmd 0 "safe <()" "diff <(cat ./a) <(cat ./b)"

echo ""
echo "=== Backticks ==="
test_cmd 2 "unsafe backticks" "echo \`cat /Users/nobody/outside\`"
test_cmd 2 "nested backticks+\$()" "echo \`cat \$(cat /Users/nobody/outside2)\`"
test_cmd 0 "safe backticks" "echo \`cat ./file\`"

echo ""
echo "=== Nested Substitutions ==="
# Backticks inside $()
test_cmd 2 "unsafe backticks in \$()" "echo \$(echo \`cat /Users/nobody/outside\`)"
test_cmd 0 "safe backticks in \$()" "echo \$(echo \`cat ./file\`)"
# $() inside $()
test_cmd 2 "unsafe nested \$()" "echo \$(echo \$(cat /Users/nobody/outside))"
test_cmd 0 "safe nested \$()" "echo \$(echo \$(cat ./file))"
# Triple nesting
test_cmd 2 "triple nested unsafe" "echo \$(echo \$(echo \`cat /Users/nobody/outside\`))"
test_cmd 0 "triple nested safe" "echo \$(echo \$(echo \`cat ./file\`))"
# Mixed with process substitution
test_cmd 2 "backticks in <()" "diff <(echo \`cat /Users/nobody/outside\`) ./file"
test_cmd 0 "safe backticks in <()" "diff <(echo \`cat ./file\`) ./other"
# Backticks with redirects inside
test_cmd 2 "backticks with redirect" "echo \`cat /Users/nobody/outside > ./out\`"
test_cmd 0 "safe backticks with redirect" "echo \`cat ./file > ./out\`"

echo ""
echo "=== Substitutions Inside Quotes ==="
# $() inside double quotes - shlex doesn't split, must scan raw string
test_cmd 2 "\$() in double quotes" 'echo "hello $(cat /Users/nobody/outside)"'
test_cmd 0 "safe \$() in double quotes" 'echo "hello $(cat ./file)"'
# Backticks inside double quotes
test_cmd 2 "backticks in double quotes" 'echo "hello `cat /Users/nobody/outside`"'
test_cmd 0 "safe backticks in double quotes" 'echo "hello `cat ./file`"'
# Process substitution reference in quotes
test_cmd 2 "<() in double quotes" 'cat "$(cat /Users/nobody/outside)"'
# Nested inside quotes
test_cmd 2 "nested \$() in quotes" 'echo "$(echo $(cat /Users/nobody/outside))"'
# Escaped backticks for nesting (old-style shell)
test_cmd 2 "escaped backticks nesting" 'echo `echo \`cat /Users/nobody/outside\``'
test_cmd 0 "safe escaped backticks" 'echo `echo \`cat ./file\``'

echo ""
echo "=== Complex Nested Substitutions ==="
# Mixed $() and backticks
test_cmd 2 "\$() inside backticks" 'echo `cat $(echo /Users/nobody/outside)`'
test_cmd 2 "backticks inside \$()" 'echo $(cat `echo /Users/nobody/outside`)'
test_cmd 0 "safe mixed nesting" 'echo $(cat `echo ./file`)'

# Triple+ nesting with mixed syntax
test_cmd 2 "triple: \$() > backtick > \$()" 'echo $(echo `echo $(cat /Users/nobody/outside)`)'
test_cmd 2 "triple: backtick > \$() > backtick" 'echo `echo $(echo \`cat /Users/nobody/outside\`)`'
test_cmd 0 "safe triple mixed" 'echo $(echo `echo $(cat ./file)`)'

# Process substitution with nested commands
test_cmd 2 "<() with nested backticks" 'diff <(cat `echo /Users/nobody/outside`) ./file'
test_cmd 2 "<() with nested \$()" 'diff <(cat $(echo /Users/nobody/outside)) ./file'
test_cmd 2 ">() with nested backticks" 'tee >(cat `echo /Users/nobody/outside`)'
test_cmd 0 "safe <() with nesting" 'diff <(cat $(echo ./a)) ./b'

# Quoting mixed with substitution
test_cmd 2 "double-quoted \$() with backticks" 'echo "$(cat `echo /Users/nobody/outside`)"'
test_cmd 2 "double-quoted backticks with \$()" 'echo "`cat $(echo /Users/nobody/outside)`"'
test_cmd 2 "path built from pieces" 'cat $(echo /etc)/passwd'
test_cmd 2 "path in nested quotes" 'echo "$(echo "$(cat /Users/nobody/outside)")"'

# Escaped chars that should NOT execute
test_cmd 0 "escaped \$ in double quotes" 'echo "\$(cat /Users/nobody/outside)"'
test_cmd 0 "single quotes block subst" "echo '\$(cat /Users/nobody/outside)'"
test_cmd 0 "single quotes block backticks" "echo '\`cat /Users/nobody/outside\`'"

# ANSI-C quoting ($'...') - no substitution inside
test_cmd 2 "real \$() after ANSI-C" "echo \$'safe' \$(cat /Users/nobody/outside)"
test_cmd 0 "ANSI-C quoting" "echo \$'/Users/nobody/outside'"
test_cmd 0 "ANSI-C with \$() inside" "echo \$'\$(cat /Users/nobody/outside)'"
test_cmd 0 "ANSI-C with escaped quote" "echo \$'safe\\'\$(cat /Users/nobody/outside)'"

echo ""
echo "=== Escape Sequences ==="
# Escaped $ - substitution doesn't execute, content is literal
test_cmd 0 "\\\$ basic" 'echo \$foo'
test_cmd 0 "\\\$((...)) arithmetic" 'echo \$((1+1))'
test_cmd 0 "\\\$ in dquotes" 'echo "price is \$100"'
test_cmd 0 "\\\$() escaped" 'echo \$(cat /Users/nobody/outside)'
test_cmd 0 "\\\$((cmd)) escaped" 'echo \$((cat /Users/nobody/outside))'

# Double backslash = escaped backslash + real substitution (executes!)
test_cmd 2 "\\\\\$() executes" 'echo \\$(cat /Users/nobody/outside)'

# Nested real substitution inside escaped outer (inner executes!)
test_cmd 2 "unescaped inside escaped \$()" 'echo \$(foo $(cat /Users/nobody/outside))'
test_cmd 2 "unescaped inside escaped backtick" 'echo \`foo `cat /Users/nobody/outside``'

# Escaped backticks - \` is literal char, paths may still flag depending on tokenization
test_cmd 2 "\\\\\` executes" 'echo \\`cat /Users/nobody/outside`'
test_cmd 2 "\\\\\` path as cmd" 'echo \\`/Users/nobody/outside`'
test_cmd 0 "\\\` at start" 'echo \`not a command'
test_cmd 0 "\\\` in dquotes" 'echo "backtick: \` here"'
test_cmd 0 "\\\` paired (literal)" 'echo \`cat /Users/nobody/outside\`notclosed'
test_cmd 0 "\\\` wrapping path (relative)" 'echo \`/Users/nobody/outside\`'
test_cmd 0 "\\\\\` relative cmd" 'echo \\`cat/Users/nobody/outside`'

# Other escapes
test_cmd 2 "unescaped in dquotes" 'echo "result: $(cat /Users/nobody/outside)"'
test_cmd 0 "trailing backslash" 'echo test\'

# Here-string/heredoc markers (should not trigger)
test_cmd 0 "<<< safe" 'cat <<< "hello"'
test_cmd 0 "<< heredoc marker" 'cat << EOF'

# Multiple substitutions in one command
test_cmd 2 "two unsafe \$()" 'echo $(cat /Users/nobody/outside) $(cat /Users/nobody/outside2)'
test_cmd 2 "one safe one unsafe" 'echo $(cat ./file) $(cat /Users/nobody/outside)'
test_cmd 2 "unsafe in second backtick" 'echo `cat ./a` `cat /Users/nobody/outside`'

# Deeply nested (4+ levels)
test_cmd 2 "quad nested" 'echo $(echo $(echo $(echo $(cat /Users/nobody/outside))))'
test_cmd 2 "quad mixed" 'echo `echo $(echo \`echo $(cat /Users/nobody/outside)\`)`'
test_cmd 0 "safe quad nested" 'echo $(echo $(echo $(echo $(cat ./file))))'

# Redirect inside substitution
test_cmd 2 "redirect in \$()" 'echo $(cat /Users/nobody/outside > /tmp/x)'
test_cmd 2 "redirect in backticks" 'echo `cat /Users/nobody/outside > /tmp/x`'
test_cmd 2 "input redirect in \$()" 'echo $(cat < /Users/nobody/outside)'

# Quoted content with parens inside substitutions (quote-aware paren matching)
test_cmd 2 "path after quoted parens" 'echo $(echo "foo()" /Users/nobody/outside)'
test_cmd 2 "path with quoted parens" 'cat $(echo "test()" /Users/nobody/outside)'
test_cmd 0 "single-quoted parens in \$()" 'echo $(echo '\''foo(bar)'\'')'
test_cmd 0 "double-quoted parens in \$()" 'echo $(echo "foo(bar)")'
test_cmd 0 "escaped paren in \$()" 'echo $(echo foo\(bar\))'
test_cmd 0 "complex quoted parens" 'echo $(echo "a]b(c)d" '\''e(f)g'\'')'
test_cmd 0 "nested quotes with parens" 'echo $(echo "outer($(echo inner))")'
test_cmd 0 "mixed quotes parens safe" 'echo $(foo "a]b(" '\''c)d'\'' )'

# Escaped process substitutions \<() and \>()
test_cmd 2 "<() executes" 'cat <(cat /Users/nobody/outside)'
test_cmd 2 ">() executes" 'diff >(cat /Users/nobody/outside) ./file'
test_cmd 0 "\\\<() escaped" 'echo \<(cat /Users/nobody/outside)'
test_cmd 0 "\\\>() escaped" 'echo \>(cat /Users/nobody/outside)'

echo ""
echo "=== Edge Cases ==="
test_cmd 2 "double-quoted outside" 'cat "/Users/nobody/outside"'
test_cmd 2 "single-quoted outside" "cat '/Users/nobody/outside'"
test_cmd 0 "empty command" ""
test_cmd 0 "no paths" "echo hello world"
test_cmd 0 "double-quoted CWD" 'cat "./file.txt"'

echo ""
echo "=== Command Separators ==="
# Semicolon (;)
test_cmd 2 "semicolon unsafe first" "cat /Users/nobody/outside; ls ./"
test_cmd 2 "semicolon unsafe middle" "ls ./; cat /Users/nobody/outside; echo done"
test_cmd 2 "semicolon unsafe last" "ls ./; echo done; cat /Users/nobody/outside"
test_cmd 0 "semicolon all safe" "ls ./a; cat ./b; echo done"

# Logical AND (&&)
test_cmd 2 "&& unsafe first" "cat /Users/nobody/outside && ls ./"
test_cmd 2 "&& unsafe middle" "ls ./ && cat /Users/nobody/outside && echo done"
test_cmd 2 "&& unsafe last" "ls ./ && echo done && cat /Users/nobody/outside"
test_cmd 0 "&& all safe" "ls ./a && cat ./b && echo done"

# Logical OR (||)
test_cmd 2 "|| unsafe first" "cat /Users/nobody/outside || ls ./"
test_cmd 2 "|| unsafe middle" "ls ./ || cat /Users/nobody/outside || echo done"
test_cmd 2 "|| unsafe last" "ls ./ || echo done || cat /Users/nobody/outside"
test_cmd 0 "|| all safe" "ls ./a || cat ./b || echo done"

# Background (&)
test_cmd 2 "& unsafe first" "cat /Users/nobody/outside & ls ./"
test_cmd 2 "& unsafe second" "ls ./ & cat /Users/nobody/outside"
test_cmd 0 "trailing & safe" "sleep 1 &"
test_cmd 0 "& all safe" "ls ./a & cat ./b"

# Pipes (|)
test_cmd 2 "pipe unsafe input" "cat /Users/nobody/outside | grep root"
test_cmd 2 "pipe unsafe middle" "ls ./ | cat /Users/nobody/outside | sort"
test_cmd 0 "pipe to system path (kernel denies write)" "cat ./file | tee /etc/log"
test_cmd 0 "pipe all safe" "cat ./file | grep pattern | sort > ./out"

# Subshell with ()
test_cmd 2 "subshell unsafe" "(cat /Users/nobody/outside)"
test_cmd 2 "subshell mixed" "(ls ./a; cat /Users/nobody/outside)"
test_cmd 2 "nested subshell unsafe" "((ls ./a); (cat /Users/nobody/outside))"
test_cmd 0 "nested subshell safe" "((ls ./a); (cat ./b))"
test_cmd 0 "subshell safe" "(ls ./a; cat ./b)"

# Mixed separators
test_cmd 2 "mixed separators unsafe" "ls ./a && cat /Users/nobody/outside || echo fail"
test_cmd 2 "complex chain unsafe" "(ls ./a && cat ./b) || (cat /Users/nobody/outside; echo done)"
test_cmd 0 "complex chain safe" "(ls ./a && cat ./b) || (echo fail; touch ./c)"
test_cmd 0 "mixed separators safe" "ls ./a && cat ./b || echo fail; touch ./c"

# Edge cases with separators
test_cmd 2 "separator with redirect unsafe" "ls ./a > ./out; cat ./b >> /etc/log"
test_cmd 0 "multiple semicolons" "echo a;; echo b"
test_cmd 0 "separator with redirect safe" "ls ./a > ./out; cat ./b >> ./out"

echo ""
echo "=== Real-World Commands ==="
test_cmd 2 "docker mount outside" "docker run -v /etc:/mnt img"
test_cmd 0 "git status" "git status"
test_cmd 0 "git diff" "git diff ./file.txt"
test_cmd 0 "grep recursive" "grep -r pattern ./src"
test_cmd 0 "find in CWD" "find . -name '*.py'"
test_cmd 0 "find system" "find /etc -name '*.conf'"
test_cmd 0 "tar create" "tar -czf ./backup.tar.gz ./src"
test_cmd 0 "tar extract system (kernel denies write)" "tar -xzf ./archive.tar.gz -C /opt"
test_cmd 0 "python script CWD" "python3 ./script.py"
test_cmd 0 "python script system" "python3 /opt/script.py"
test_cmd 0 "npm test" "npm test"
test_cmd 0 "curl output system (kernel denies write)" "curl -o /etc/file https://example.com"
test_cmd 0 "curl output CWD" "curl -o ./downloaded.txt https://example.com"
test_cmd 0 "rsync system (kernel denies write)" "rsync -av ./src /opt/dest"

echo ""
echo "=== Sed Patterns ==="
# Substitution patterns - slashes are delimiters, not paths
test_cmd 0 "sed basic subst" "sed 's/foo/bar/' ./file"
test_cmd 0 "sed global subst" "sed 's/foo/bar/g' ./file"
test_cmd 0 "sed alternate delim" "sed 's|foo|bar|' ./file"
test_cmd 0 "sed escaped slashes" "sed 's/path\\/to/other/' ./file"
test_cmd 0 "sed multiple -e" "sed -e 's/a/b/' -e 's/c/d/' ./file"
test_cmd 0 "sed path-like pattern" "sed 's~/usr/bin~local~' ./file"
# Address patterns starting with / look like paths (FP - requires command-aware parsing)
test_cmd 0 "sed addr /pattern/d" "sed '/pattern/d' ./file"
test_cmd 0 "sed addr /x/p" "sed -n '/match/p' ./file"
# Real file arguments - should be validated
test_cmd 0 "sed -i safe file" "sed -i 's/a/b/' ./config"
test_cmd 0 "sed -i system (kernel denies write)" "sed -i 's/a/b/' /etc/config"
test_cmd 0 "sed -f safe script" "sed -f ./script.sed ./file"
test_cmd 0 "sed -f system script" "sed -f /etc/sed.script ./file"
# Safe patterns
test_cmd 0 "sed numeric range" "sed -n '1,10p' ./file"
test_cmd 0 "sed regex special" "sed 's/.*/prefix: &/' ./file"

echo ""
echo "=== Awk/Grep/Perl Patterns ==="
# Patterns starting with / look like paths (FP - requires command-aware parsing)
test_cmd 0 "awk /pattern/" "awk '/pattern/ {print}' ./file"
test_cmd 0 "grep -E regex" "grep -E '/[a-z]+/' ./file"
test_cmd 0 "perl /pattern/" "perl -ne '/pattern/ && print' ./file"
test_cmd 0 "cut -d/ delimiter" "cut -d/ -f1 ./file"
# Safe patterns (no leading /)
test_cmd 0 "awk field sep" "awk -F: '{print \$1}' ./file"
test_cmd 0 "grep basic" "grep pattern ./file"
test_cmd 0 "perl subst" "perl -pe 's/foo/bar/' ./file"
# Real file arguments - should be validated
test_cmd 0 "awk -f safe" "awk -f ./script.awk ./data"
test_cmd 0 "awk -f system script" "awk -f /var/script.awk ./data"
test_cmd 0 "grep -r safe" "grep -r pattern ./src"
test_cmd 0 "grep -r system" "grep -r pattern /var/log"

echo ""
echo "=== Internal Failure Handling ==="
# A hook that cannot validate must not read as approval. Codex treats an empty
# response as approval, so a crash would silently disable the check for it while
# blocking Claude. Malformed input stands in for any unexpected failure.
refusal_on_failure() {
    local output decision
    output=$(printf 'not json' | python3 "$HOOK" --agent "$AGENT" 2>/dev/null)
    if [[ "$AGENT" == "claude" ]]; then
        decision=$(echo "$output" | jq -r '.decision // "error"')
    else
        decision=$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision // "error"')
    fi
    if [[ "$decision" == "block" || "$decision" == "deny" ]]; then
        echo "✓ malformed payload refused"
        ((PASS++))
    else
        echo "✗ malformed payload refused"
        echo "  expected a refusal, got: ${output:-<empty>}"
        ((FAIL++))
    fi
}
refusal_on_failure

echo ""
echo "================================"
echo "Path Validation: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "All tests passed!" || exit 1

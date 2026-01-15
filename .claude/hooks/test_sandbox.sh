#!/bin/bash
# Comprehensive test suite for sandboxing.
# Run: ./test_sandbox.sh

HOOK="${HOOK:-$HOME/.claude/hooks/path_check.py}"
CWD="${CWD:-$PWD}"
export EVIL=/etc  # For env var expansion tests
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$CWD}"  # Simulate Claude's env
PASS=0
FAIL=0

test_cmd() {
    local expected="$1" desc="$2" cmd="$3"
    # Use jq to properly escape the command for JSON
    local input output decision
    input=$(jq -n --arg cmd "$cmd" --arg cwd "$CWD" '{"tool_input":{"command":$cmd},"cwd":$cwd}')
    output=$(echo "$input" | python3 "$HOOK" 2>/dev/null)
    decision=$(echo "$output" | jq -r '.decision // "error"')
    if [[ "$decision" == "approve" ]]; then
        result=0
    else
        result=2
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
test_cmd 0 "CWD relative" "cat ./file.txt"
test_cmd 0 "CWD nested" "cat ./dir/subdir/file.txt"
test_cmd 0 "CWD implicit (no slash)" "cat file.txt"
test_cmd 0 "/tmp absolute" "touch /tmp/test"
test_cmd 0 "/tmp nested" "cat /tmp/foo/bar/baz"
test_cmd 0 "/private/tmp (macOS)" "touch /private/tmp/file"
test_cmd 2 "outside /etc" "cat /etc/passwd"
test_cmd 2 "outside /var" "ls /var/log"
test_cmd 2 "outside /opt" "cat /opt/file"
test_cmd 2 "outside root" "ls /"
test_cmd 2 "parent traversal" "cat ../../../etc/passwd"
test_cmd 2 "/var/tmp (not /tmp)" "touch /var/tmp/file"

echo ""
echo "=== Tilde Expansion ==="
test_cmd 2 "tilde home outside" "cat ~/.bashrc"
test_cmd 2 "tilde in flag" "cmd --config=~/.config/app"
test_cmd 2 "tilde ssh" "cat ~/.ssh/id_rsa"
test_cmd 2 "tilde redirect" "echo test > ~/output.txt"
test_cmd 2 "tilde .cache blocked" "ls ~/.cache"

echo ""
echo "=== ~/.claude Exception ==="
test_cmd 0 "~/.claude allowed" "ls ~/.claude"
test_cmd 0 "~/.claude subdir" "cat ~/.claude/settings.json"
test_cmd 0 "~/.claude nested" "ls ~/.claude/hooks/path_check.py"
test_cmd 0 "~/.claude redirect" "echo test > ~/.claude/test.txt"
test_cmd 0 "~/.claude in flag" "cmd --config=~/.claude/config"
test_cmd 0 "\$HOME/.claude" 'ls $HOME/.claude'
test_cmd 0 "\$HOME/.claude subdir" 'cat $HOME/.claude/settings.json'

echo ""
echo "=== Environment Variable Paths ==="
# Note: These tests require EVIL=/etc to be set
test_cmd 2 "env var /etc path" 'cat $EVIL/passwd'
test_cmd 2 "env var in redirect" 'echo test > $EVIL/file'
test_cmd 2 "HOME subdir blocked" 'ls $HOME/.cache'
test_cmd 0 "TMPDIR safe" 'ls $TMPDIR'

echo ""
echo "=== Flags ==="
test_cmd 0 "short flags" "ls -la"
test_cmd 0 "long flags" "grep --recursive pattern"
test_cmd 0 "multiple flags" "ls -la -h --color=auto"
test_cmd 0 "flag with value" "cmd -o output.txt"

echo ""
echo "=== Flag-Embedded Paths ==="
test_cmd 2 "gcc -I outside" "gcc -I/usr/include main.c"
test_cmd 2 "--prefix outside" "./configure --prefix=/usr/local"
test_cmd 2 "--config outside" "cmd --config=/etc/app.conf"
test_cmd 0 "-I to CWD" "gcc -I./include main.c"
test_cmd 0 "--output to /tmp" "cmd --output=/tmp/file"
test_cmd 0 "-o to CWD" "gcc -o ./output main.c"
test_cmd 2 "-L outside" "gcc -L/usr/lib main.c"
test_cmd 0 "flag=value no path" "cmd --verbose=true"

echo ""
echo "=== Redirections ==="
test_cmd 2 "stdout > outside" "echo test > /etc/foo"
test_cmd 2 "stdout >> outside" "echo test >> /var/log/app.log"
test_cmd 2 "stderr 2> outside" "cmd 2> /etc/errors"
test_cmd 2 "both &> outside" "cmd &> /etc/output"
test_cmd 2 "fd >& outside" "cmd >& /etc/log"
test_cmd 0 "redirect to CWD" "echo test > ./output.txt"
test_cmd 0 "redirect to /tmp" "echo test > /tmp/output.txt"
test_cmd 2 "<> outside" "cmd <>/etc/file"
test_cmd 0 "<> to /dev/tty" "cmd <>/dev/tty"
test_cmd 0 "stdin < from CWD" "cmd < ./input.txt"
test_cmd 2 "stdin < outside" "cmd < /etc/passwd"

echo ""
echo '=== Command Substitution $() ==='
test_cmd 0 "safe \$()" "echo \$(cat ./file)"
test_cmd 2 "unsafe \$()" "echo \$(cat /etc/passwd)"
test_cmd 0 "safe nested \$()" "echo \$(cat \$(ls ./))"
test_cmd 2 "unsafe nested \$()" "echo \$(cat \$(cat /etc/hosts))"
test_cmd 0 "multiple safe \$()" "echo \$(cat ./a) \$(cat ./b)"
test_cmd 2 "mixed safe/unsafe \$()" "echo \$(cat ./a) \$(cat /etc/passwd)"
test_cmd 2 "deeply nested unsafe" "echo \$(echo \$(echo \$(cat /etc/passwd)))"

echo ""
echo "=== Process Substitution <() >() ==="
test_cmd 0 "safe <()" "diff <(cat ./a) <(cat ./b)"
test_cmd 2 "unsafe <()" "diff <(cat /etc/passwd) ./b"
test_cmd 0 "safe >()" "tee >(cat > ./log)"
test_cmd 2 "unsafe >()" "tee >(cat > /etc/log)"
test_cmd 2 "nested in <()" "diff <(cat \$(cat /etc/x)) ./b"

echo ""
echo "=== Backticks ==="
test_cmd 0 "safe backticks" "echo \`cat ./file\`"
test_cmd 2 "unsafe backticks" "echo \`cat /etc/passwd\`"
test_cmd 2 "nested backticks+\$()" "echo \`cat \$(cat /etc/hosts)\`"

echo ""
echo "=== Edge Cases ==="
test_cmd 0 "empty command" ""
test_cmd 0 "no paths" "echo hello world"
test_cmd 2 "double-quoted outside" 'cat "/etc/passwd"'
test_cmd 0 "double-quoted CWD" 'cat "./file.txt"'
test_cmd 2 "single-quoted outside" "cat '/etc/passwd'"

echo ""
echo "=== Command Separators ==="
# Semicolon (;)
test_cmd 0 "semicolon all safe" "ls ./a; cat ./b; echo done"
test_cmd 2 "semicolon unsafe first" "cat /etc/passwd; ls ./"
test_cmd 2 "semicolon unsafe middle" "ls ./; cat /etc/passwd; echo done"
test_cmd 2 "semicolon unsafe last" "ls ./; echo done; cat /etc/passwd"

# Logical AND (&&)
test_cmd 0 "&& all safe" "ls ./a && cat ./b && echo done"
test_cmd 2 "&& unsafe first" "cat /etc/passwd && ls ./"
test_cmd 2 "&& unsafe middle" "ls ./ && cat /etc/passwd && echo done"
test_cmd 2 "&& unsafe last" "ls ./ && echo done && cat /etc/passwd"

# Logical OR (||)
test_cmd 0 "|| all safe" "ls ./a || cat ./b || echo done"
test_cmd 2 "|| unsafe first" "cat /etc/passwd || ls ./"
test_cmd 2 "|| unsafe middle" "ls ./ || cat /etc/passwd || echo done"
test_cmd 2 "|| unsafe last" "ls ./ || echo done || cat /etc/passwd"

# Background (&)
test_cmd 0 "& all safe" "ls ./a & cat ./b"
test_cmd 2 "& unsafe first" "cat /etc/passwd & ls ./"
test_cmd 2 "& unsafe second" "ls ./ & cat /etc/passwd"
test_cmd 0 "trailing & safe" "sleep 1 &"

# Pipes (|)
test_cmd 0 "pipe all safe" "cat ./file | grep pattern | sort > ./out"
test_cmd 2 "pipe unsafe input" "cat /etc/passwd | grep root"
test_cmd 2 "pipe unsafe output" "cat ./file | tee /etc/log"
test_cmd 2 "pipe unsafe middle" "ls ./ | cat /etc/passwd | sort"

# Subshell with ()
test_cmd 0 "subshell safe" "(ls ./a; cat ./b)"
test_cmd 2 "subshell unsafe" "(cat /etc/passwd)"
test_cmd 2 "subshell mixed" "(ls ./a; cat /etc/passwd)"
test_cmd 0 "nested subshell safe" "((ls ./a); (cat ./b))"
test_cmd 2 "nested subshell unsafe" "((ls ./a); (cat /etc/passwd))"

# Mixed separators
test_cmd 0 "mixed separators safe" "ls ./a && cat ./b || echo fail; touch ./c"
test_cmd 2 "mixed separators unsafe" "ls ./a && cat /etc/passwd || echo fail"
test_cmd 0 "complex chain safe" "(ls ./a && cat ./b) || (echo fail; touch ./c)"
test_cmd 2 "complex chain unsafe" "(ls ./a && cat ./b) || (cat /etc/passwd; echo done)"

# Edge cases with separators
test_cmd 0 "multiple semicolons" "echo a;; echo b"
test_cmd 0 "separator with redirect safe" "ls ./a > ./out; cat ./b >> ./out"
test_cmd 2 "separator with redirect unsafe" "ls ./a > ./out; cat ./b >> /etc/log"

echo ""
echo "=== Real-World Commands ==="
test_cmd 0 "git status" "git status"
test_cmd 0 "git diff" "git diff ./file.txt"
test_cmd 0 "grep recursive" "grep -r pattern ./src"
test_cmd 0 "find in CWD" "find . -name '*.py'"
test_cmd 2 "find outside" "find /etc -name '*.conf'"
test_cmd 0 "tar create" "tar -czf ./backup.tar.gz ./src"
test_cmd 2 "tar extract outside" "tar -xzf ./archive.tar.gz -C /opt"
test_cmd 0 "python script CWD" "python3 ./script.py"
test_cmd 2 "python script outside" "python3 /opt/script.py"
test_cmd 0 "npm test" "npm test"
test_cmd 2 "docker mount outside" "docker run -v /etc:/mnt img"
test_cmd 2 "curl output outside" "curl -o /etc/file https://example.com"
test_cmd 0 "curl output CWD" "curl -o ./downloaded.txt https://example.com"
test_cmd 2 "rsync outside" "rsync -av ./src /opt/dest"

echo ""
echo "================================"
echo "Path Validation: $PASS passed, $FAIL failed"

# Reset counters for execution tests
EXEC_PASS=0
EXEC_FAIL=0

test_exec() {
    local expected="$1" desc="$2"
    shift 2
    local code="$*"

    if python3 -c "$code" 2>/dev/null; then
        result=0
    else
        result=1
    fi

    if [[ "$result" -eq "$expected" ]]; then
        echo "✓ $desc"
        ((EXEC_PASS++))
    else
        echo "✗ $desc"
        echo "  expected: $expected, got: $result"
        ((EXEC_FAIL++))
    fi
}

echo ""
echo "=== Execution Sandbox: Write Restrictions ==="
test_exec 1 "Block write to /etc" "open('/etc/sandbox_test', 'w').write('test')"
test_exec 1 "Block write to /var" "open('/var/sandbox_test', 'w').write('test')"
test_exec 1 "Block write to home root" "open('$HOME/sandbox_test', 'w').write('test')"
test_exec 0 "Allow write to /tmp" "open('/tmp/sandbox_test', 'w').write('test'); import os; os.unlink('/tmp/sandbox_test')"
test_exec 0 "Allow write to CWD" "open('$CWD/.sandbox_test', 'w').write('test'); import os; os.unlink('$CWD/.sandbox_test')"

echo ""
echo "=== Execution Sandbox: Read Restrictions ==="
test_exec 0 "Allow read from /etc/passwd (read-only)" "open('/etc/passwd').read()"
test_exec 1 "Block read from ~/.zshrc" "open('$HOME/.zshrc').read()"
test_exec 0 "Allow read from CWD" "import os; cwd='$CWD'; files=[f for f in os.listdir(cwd) if os.path.isfile(os.path.join(cwd,f))]; open(os.path.join(cwd,files[0])).read() if files else None"

echo ""
echo "=== Execution Sandbox: Directory Listing ==="
test_exec 0 "Allow listing home directory" "import os; os.listdir('$HOME')"
test_exec 0 "Allow listing CWD" "import os; os.listdir('$CWD')"
test_exec 0 "Allow listing /tmp" "import os; os.listdir('/tmp')"

echo ""
echo "=== Execution Sandbox: Subprocess ==="
test_exec 0 "Allow subprocess ls" "import subprocess; subprocess.run(['ls','-la','$CWD'],capture_output=True,timeout=5,check=True)"
test_exec 0 "Allow subprocess cat /etc/passwd" "import subprocess; subprocess.run(['cat','/etc/passwd'],capture_output=True,timeout=5,check=True)"

echo ""
echo "=== Execution Sandbox: Device Files ==="
test_exec 0 "Allow read /dev/null" "open('/dev/null', 'r').read()"
test_exec 0 "Allow write /dev/null" "open('/dev/null', 'w').write('test')"
test_exec 0 "Allow read /dev/urandom" "open('/dev/urandom', 'rb').read(32)"
test_exec 0 "Allow read /dev/zero" "open('/dev/zero', 'rb').read(32)"
test_exec 0 "Allow /dev/stdout" "import os; os.write(1, b'')"
test_exec 0 "Allow /dev/stderr" "import os; os.write(2, b'')"

echo ""
echo "=== Execution Sandbox: macOS Temp Directories ==="
test_exec 0 "Allow write /var/folders" "import tempfile; f=tempfile.NamedTemporaryFile(delete=True); f.write(b'test'); f.close()"
test_exec 0 "Allow write /private/tmp" "open('/private/tmp/sandbox_test', 'w').write('test'); import os; os.unlink('/private/tmp/sandbox_test')"

echo ""
echo "=== Execution Sandbox: Network ==="
test_exec 0 "Allow socket creation" "import socket; s=socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.close()"
test_exec 0 "Allow DNS resolution" "import socket; socket.gethostbyname('localhost')"
test_exec 0 "Allow HTTP request" "import urllib.request; urllib.request.urlopen('http://httpbin.org/get', timeout=5).read(100)"

echo ""
echo "=== Execution Sandbox: Sensitive Home Directories ==="
test_exec 1 "Block read ~/.ssh" "import os; os.listdir('$HOME/.ssh') if os.path.exists('$HOME/.ssh') else (_ for _ in ()).throw(PermissionError())"
test_exec 1 "Block read ~/.gnupg" "import os; os.listdir('$HOME/.gnupg') if os.path.exists('$HOME/.gnupg') else (_ for _ in ()).throw(PermissionError())"
test_exec 1 "Block read ~/.aws/credentials" "open('$HOME/.aws/credentials').read() if __import__('os').path.exists('$HOME/.aws/credentials') else (_ for _ in ()).throw(PermissionError())"

echo ""
echo "=== Execution Sandbox: File Operations ==="
test_exec 0 "Allow file stat in CWD" "import os; os.stat('$CWD')"
test_exec 0 "Allow file stat /tmp" "import os; os.stat('/tmp')"
test_exec 0 "Allow getcwd" "import os; os.getcwd()"
test_exec 0 "Allow chmod in CWD" "import os; f='$CWD/.chmod_test'; open(f,'w').close(); os.chmod(f, 0o644); os.unlink(f)"
test_exec 0 "Allow symlink in CWD" "import os; f='$CWD/.link_test'; t='$CWD/.link_target'; open(t,'w').close(); os.path.exists(f) and os.unlink(f); os.symlink(t,f); os.unlink(f); os.unlink(t)"

echo ""
echo "=== Execution Sandbox: Environment ==="
test_exec 0 "Allow read env vars" "import os; os.environ.get('HOME')"
test_exec 0 "Allow modify env vars" "import os; os.environ['SANDBOX_TEST']='1'; del os.environ['SANDBOX_TEST']"

echo ""
echo "================================"
echo "Execution Sandbox: $EXEC_PASS passed, $EXEC_FAIL failed"
echo ""
echo "================================"
TOTAL_PASS=$((PASS + EXEC_PASS))
TOTAL_FAIL=$((FAIL + EXEC_FAIL))
echo "Total: $TOTAL_PASS passed, $TOTAL_FAIL failed"
[[ $TOTAL_FAIL -eq 0 ]] && echo "All tests passed!" || exit 1

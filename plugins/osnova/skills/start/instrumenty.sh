#!/bin/bash
# Windows (Git Bash). Ставит программы пакета в ~/.local/bin (то есть C:\Users\<имя>\.local\bin — туда же
# встаёт сам Claude): связь с GitHub (gh), сканер секретов (gitleaks), проверка кода (ruff);
# railway — только по просьбе (`instrumenty.sh railway`). Права администратора не нужны, всего ~100 МБ.
# Что уже есть — не трогает. Версии и контрольные суммы закреплены: подменённый файл не поставится.
# Новая версия — только правкой здесь. В конце папка программ дописывается в путь Windows: так их находят
# и Git Bash, и все новые окна.
BIN="$HOME/.local/bin"
PATH="$BIN:$PATH"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$BIN"
bad=0

# unpack <архив.zip> <папка>: unzip из Git Bash; нет его (старый Git) — tar.exe из Windows 10 (zip тоже читает),
# и последний запас — PowerShell. KOROBEINIKOV_NO_UNZIP=1 включает запасные способы для проверки.
unpack() {
  if [ "${KOROBEINIKOV_NO_UNZIP:-}" != 1 ] && command -v unzip >/dev/null; then unzip -q "$1" -d "$2"; return; fi
  local tar
  tar="$(cygpath -u "${SYSTEMROOT:-C:\\Windows}" 2>/dev/null)/System32/tar.exe"
  if [ -x "$tar" ] && "$tar" -xf "$(cygpath -w "$1")" -C "$(cygpath -w "$2")"; then echo "   (распаковано через tar.exe)"; return; fi
  powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command \
    "Expand-Archive -LiteralPath '$(cygpath -w "$1")' -DestinationPath '$(cygpath -w "$2")' -Force" \
    && echo "   (распаковано через PowerShell)"
}

# get <программа> <адрес файла (.zip)> <контрольная сумма>
get() {
  local name=$1 url=$2 found
  if command -v "$name" >/dev/null; then echo "✅ $name уже есть"; return; fi
  if ! curl -fsSL -o "$T/$name.zip" "$url"; then
    echo "❌ $name не скачался — проверь интернет и запусти снова"; bad=1; return
  fi
  if [ "$( (shasum -a 256 "$T/$name.zip" 2>/dev/null || sha256sum "$T/$name.zip") | cut -d' ' -f1)" != "$3" ]; then
    echo "❌ $name: файл не совпал с контрольной суммой — не ставлю, сообщи автору пакета"; bad=1; return
  fi
  mkdir "$T/$name"
  unpack "$T/$name.zip" "$T/$name" || { echo "❌ $name не распаковался — сообщи автору пакета"; bad=1; return; }
  found=$(find "$T/$name" -type f -name "$name.exe" | head -1)
  if [ -n "$found" ] && mv "$found" "$BIN/$name.exe" && "$BIN/$name.exe" --version >/dev/null; then
    echo "✅ $name поставлен"
  else
    echo "❌ $name не запустился — сообщи автору пакета"; bad=1
  fi
}

# Папка программ — в путь пользователя Windows (если её там ещё нет)
add_to_path() {
  command -v cygpath >/dev/null && command -v powershell.exe >/dev/null || return 0
  local out
  cat > "$T/path.ps1" <<'EOF'
$d = $env:KB_BIN.TrimEnd('\')
$p = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not ($p -split ';' | Where-Object { $_.TrimEnd('\') -ieq $d })) {
  [Environment]::SetEnvironmentVariable('Path', $(if ($p) { "$p;$d" } else { $d }), 'User')
  'added'
}
EOF
  out=$(KB_BIN="$(cygpath -w "$BIN")" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass \
    -File "$(cygpath -w "$T/path.ps1")" 2>&1) \
    || { echo "⚠️ Не вышло дописать папку программ в путь Windows: $out"; return 0; }
  [ "$out" = added ] && echo "✅ Папка программ добавлена в путь Windows (новые окна её увидят)"
  return 0
}

# Компьютер на ARM: есть свои сборки; на обычном (x64) — x64. x64-сборки идут и на ARM, но медленнее.
case "${PROCESSOR_ARCHITEW6432:-${PROCESSOR_ARCHITECTURE:-}}" in ARM64) ARM=1 ;; *) ARM=0 ;; esac

# Railway нужен только там, где что-то выкладывают: ставится отдельно, по просьбе маршрута.
if [ "${1:-}" = railway ]; then
  RW=https://github.com/railwayapp/cli/releases/download/v5.71.0/railway-v5.71.0
  if [ $ARM = 1 ]; then
    get railway "$RW-aarch64-pc-windows-msvc.zip" 0f8e585b19c83ffdf1d975e76ff8bba6bd984e6b19fe2cebf53ca513c70c5c6f
  else
    get railway "$RW-x86_64-pc-windows-msvc.zip" 1460c5d4616794558e21bdb1bf94ff2dc2fb9a48df647857642bbe1e714f81b6
  fi
  add_to_path
  exit $bad
fi

GH=https://github.com/cli/cli/releases/download/v2.103.3/gh_2.103.3_windows
GL=https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_windows
RF=https://github.com/astral-sh/ruff/releases/download/0.17.3/ruff
if [ $ARM = 1 ]; then
  get gh "${GH}_arm64.zip" 197211c98687d7770ac331fe8a3b6c198c389108c1536cdbedf659fe4703e484
  get gitleaks "${GL}_arm64.zip" b95f5e4f5c425cedca7ee203d9afd29597e692c4924a12ed42f970537c72cc0f
  get ruff "$RF-aarch64-pc-windows-msvc.zip" 56cc54ae263ff46a30e095421ff8a93971d9c2dcad2a5e8b64eebc078cac5a16
else
  get gh "${GH}_amd64.zip" 98d0cfa794721665d7973dd728c78aff7bd836d58f10f6d7a03568eccb0a22e0
  get gitleaks "${GL}_x64.zip" d29144deff3a68aa93ced33dddf84b7fdc26070add4aa0f4513094c8332afc4e
  get ruff "$RF-x86_64-pc-windows-msvc.zip" a84d9ac74af8ef5bac84a1888a1634df18e6e985e2f930d35c052beacd00e813
fi
add_to_path
exit $bad

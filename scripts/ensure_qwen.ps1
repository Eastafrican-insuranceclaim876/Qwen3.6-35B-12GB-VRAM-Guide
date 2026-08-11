# ensure_qwen.ps1 — 按需拉起本地 Qwen3.6-35B (text_fast 档案)
# 用法: powershell -ExecutionPolicy Bypass -File <HOME>\ensure_qwen.ps1
# 行为: 若 llama-server 未运行 -> 独立进程启动 -> 等待健康检查 -> 输出状态
$ErrorActionPreference = "Continue"

$ROOT   = "<YOUR_LLAMA_CPP_DIR>"
$MODEL  = "<YOUR_MODEL_PATH>"
$LOG    = "$ROOT\qwen_apex_text_fast.log"
$PORT   = 8080

# 1) 已在运行?
$proc = Get-Process -Name "llama-server" -ErrorAction SilentlyContinue
if ($proc) {
    Write-Output "ALREADY_RUNNING pid=$($proc.Id)"
    exit 0
}

# 2) 端口被占但进程名不同?
$listener = Get-NetTCPConnection -LocalPort $PORT -State Listen -ErrorAction SilentlyContinue
if ($listener) {
    Write-Output "PORT_BUSY pid=$($listener.OwningProcess)"
    exit 0
}

# 3) 资产检查
if (-not (Test-Path $ROOT\llama-server.exe)) { Write-Output "ERROR: llama-server.exe missing"; exit 1 }
if (-not (Test-Path $MODEL)) { Write-Output "ERROR: model missing"; exit 1 }

# 4) 独立进程启动 (不依赖调用方生命周期)
$args = @(
    "-m", $MODEL,
    "-ngl", "99",
    "--n-cpu-moe", "16",
    "-c", "32768",
    "--cache-type-k", "q8_0", "--cache-type-v", "q8_0",
    "--no-mmap", "--mlock",
    "--reasoning", "off",
    "--reasoning-format", "deepseek",
    "--jinja",
    "--threads", "12",
    "--host", "127.0.0.1", "--port", "8080"
)
Start-Process -FilePath "$ROOT\llama-server.exe" -ArgumentList $args `
    -WindowStyle Hidden -RedirectStandardOutput $LOG -RedirectStandardError "$LOG.err"
Write-Output "STARTED waiting_health..."

# 5) 等待健康检查 (最多 120s，16GB 模型加载)
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 2
    try {
        $h = Invoke-RestMethod -Uri "http://127.0.0.1:$PORT/health" -TimeoutSec 3
        if ($h.status -eq "ok") {
            Write-Output "READY slot_processing=$($h.slots_processing) total=$($h.slots_idle+$h.slots_processing)"
            exit 0
        }
    } catch { }
}
Write-Output "TIMEOUT model_not_ready"
exit 2

# ensure_qwen_128k.ps1 — 拉起本地 Qwen3.6-35B (258K 原生最大上下文档)
# 用法: powershell -ExecutionPolicy Bypass -File <HOME>\ensure_qwen_128k.ps1
# 258K 最优档: ncmoe=22 + q4_0 KV (2026-08-11 实测 decode 50.9 / 45K输入85.5s; q4 KV 解决大输入 prefill 塌陷 397→85.5s)
# 悬崖规律: ctx 越大悬崖 ncmoe 越上移 (32K→16, 64K→17, 128K→20, 258K→24)
# 日常压缩用 64K 档 (60.7 更快); 258K 仅超长输入时用
$ErrorActionPreference = "Continue"

$ROOT   = "<YOUR_LLAMA_CPP_DIR>"
$MODEL  = "<YOUR_MODEL_PATH>"
$LOG    = "$ROOT\qwen_apex_258k.log"
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
    "--n-cpu-moe", "22",
    "-c", "262144",
    "--cache-type-k", "q4_0", "--cache-type-v", "q4_0",
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

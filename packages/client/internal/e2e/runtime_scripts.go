package e2e

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func ensureRuntimeScripts(root string) (string, error) {
	if strings.TrimSpace(root) == "" {
		root = filepath.Join("tmp", "e2e", "stary")
	}

	absRoot := root
	if !filepath.IsAbs(absRoot) {
		moduleRootPath, err := moduleRoot()
		if err != nil {
			return "", err
		}
		absRoot = filepath.Join(moduleRootPath, root)
	}

	if err := os.MkdirAll(absRoot, 0o750); err != nil {
		return "", fmt.Errorf("create stary dir: %w", err)
	}

	for name, content := range runtimeScriptFixtures() {
		path := filepath.Join(absRoot, name+".stary")
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			return "", fmt.Errorf("write runtime script %s: %w", name, err)
		}
	}

	return absRoot, nil
}

func runtimeScriptFixtures() map[string]string {
	return map[string]string{
		"kernel_info": `---
name: kernel_info
version: "1.0.0"
schema:
  type: object
  required: [kernel]
  properties:
    kernel:
      type: string
---
def main():
  return {"kernel": exec_cmd(cmd="uname", args=["-srmo"])}
`,
		"cpu_count": `---
name: cpu_count
version: "1.0.0"
schema:
  type: object
  required: [cpu_count]
  properties:
    cpu_count:
      type: integer
---
def main():
  out = exec_cmd(cmd="nproc")
  return {"cpu_count": int(out)}
`,
		"loadavg_linux": `---
name: loadavg_linux
version: "1.0.0"
schema:
  type: object
  required: [load_1m, load_5m, load_15m]
  properties:
    load_1m: {type: number}
    load_5m: {type: number}
    load_15m: {type: number}
---
def main():
  parts = exec_cmd(cmd="cat", args=["/proc/loadavg"]).split(" ")
  return {"load_1m": float(parts[0]), "load_5m": float(parts[1]), "load_15m": float(parts[2])}
`,
		"mem_linux": `---
name: mem_linux
version: "1.0.0"
schema:
  type: object
  required: [memory_total_bytes, memory_used_bytes, memory_used_percent]
  properties:
    memory_total_bytes: {type: integer}
    memory_used_bytes: {type: integer}
    memory_used_percent: {type: number}
---
def main():
  lines = exec_cmd(cmd="cat", args=["/proc/meminfo"]).split("\n")
  total_kb = 0
  avail_kb = 0
  for line in lines:
    if line.startswith("MemTotal:"):
      total_kb = int([c for c in line.split(" ") if c != ""][1])
    if line.startswith("MemAvailable:"):
      avail_kb = int([c for c in line.split(" ") if c != ""][1])
  total = total_kb * 1024
  used = (total_kb - avail_kb) * 1024
  pct = 0.0
  if total > 0:
    pct = (float(used) / float(total)) * 100.0
  return {"memory_total_bytes": total, "memory_used_bytes": used, "memory_used_percent": pct}
`,
		"disk_root": `---
name: disk_root
version: "1.0.0"
schema:
  type: object
  required: [root_total_bytes, root_used_bytes, root_usage_percent]
  properties:
    root_total_bytes: {type: integer}
    root_used_bytes: {type: integer}
    root_usage_percent: {type: number}
---
def main():
  lines = exec_cmd(cmd="df", args=["-B1", "/"]).split("\n")
  cols = [c for c in lines[1].split(" ") if c != ""]
  total = int(cols[1])
  used = int(cols[2])
  pct = 0.0
  if total > 0:
    pct = (float(used) / float(total)) * 100.0
  return {"root_total_bytes": total, "root_used_bytes": used, "root_usage_percent": pct}
`,
		"net_default_route": `---
name: net_default_route
version: "1.0.0"
schema:
  type: object
  required: [default_route]
  properties:
    default_route:
      type: string
---
def main():
  lines = exec_cmd(cmd="cat", args=["/proc/net/route"]).split("\n")
  for line in lines[1:]:
    cols = [c for c in line.split("\t") if c != ""]
    if len(cols) > 2 and cols[1] == "00000000":
      return {"default_route": cols[0] + ":" + cols[2]}
  return {"default_route": "unknown"}
`,
		"uptime_linux": `---
name: uptime_linux
version: "1.0.0"
schema:
  type: object
  required: [uptime_seconds]
  properties:
    uptime_seconds: {type: number}
---
def main():
  raw = exec_cmd(cmd="cat", args=["/proc/uptime"]).split(" ")[0]
  return {"uptime_seconds": float(raw)}
`,
		"top_process_cpu": `---
name: top_process_cpu
version: "1.0.0"
schema:
  type: object
  required: [top_process]
  properties:
    top_process:
      type: string
---
def main():
  return {"top_process": exec_cmd(cmd="cat", args=["/proc/1/comm"])}
`,
		"filesystem_type": `---
name: filesystem_type
version: "1.0.0"
schema:
  type: object
  required: [fs_type]
  properties:
    fs_type:
      type: string
---
def main():
  return {"fs_type": exec_cmd(cmd="stat", args=["-f", "-c", "%T", "/"])}
`,
		"proc_stat_snapshot": `---
name: proc_stat_snapshot
version: "1.0.0"
schema:
  type: object
  required: [cpu_line]
  properties:
    cpu_line:
      type: string
---
def main():
  lines = exec_cmd(cmd="cat", args=["/proc/stat"]).split("\n")
  return {"cpu_line": lines[0]}
`,
	}
}

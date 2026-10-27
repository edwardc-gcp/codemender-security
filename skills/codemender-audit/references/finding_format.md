# CodeMender Exploit & Finding Format Reference

When `cm verify <finding-id>` executes, CodeMender writes investigation and exploit artifacts directly under `${PROJECT_ROOT}/.exploit/` (cm 0.16.0). A later `cm fix` copies them into its own workspace directory (for example `app/.exploit/`).

> **Note on Sequential Verification**: Because `.exploit/PLAN.md` and `.exploit/LOG.md` may be overwritten across consecutive `cm verify` calls, inspect or archive them immediately after each verification run. Always ensure `.exploit/` is listed in `.git/info/exclude` so `cm fix` does not delete your verification artifacts.

## Artifact Directory Structure

```text
.exploit/
├── PLAN.md                # Investigation and validation checklist
├── LOG.md                 # Investigation log: commands, requests, and observations
├── REPORT.md              # Executive summary, root cause analysis, fix recommendation, reproduction
├── exploit.sh             # Standalone, executable PoC
├── info.yaml              # Machine-readable verdict (see Section 3)
└── server.log             # Runtime logs written by the PoC, when any
```

---

## 1. Official Finding Lifecycle & Triage Integrity (`OPEN`, `VERIFIED`, `FIXED`, `DISMISSED`, `REOPENED`)

Before reporting a vulnerability to the user:
1. **Official Finding States (`status`)**:
   * **`OPEN`**: Detected (or imported) finding that is active and not yet verified.
   * **`VERIFIED`**: `cm verify` confirmed exploitability (cm 0.16.0 sets this status directly).
   * **`FIXED`**: Patch synthesized, applied, passed `build.command`, and verified against PoC re-attack. Only a successful `cm fix` sets it: code fixed by hand or by the coding agent keeps its old status even after a clean diff re-scan.
   * **`DISMISSED`**: Marked by verification as a false positive, already mitigated, **or having insufficient confidence to confirm exploitability**. Because `DISMISSED` can also result from low verification confidence, still inspect the code context before assuming a dismissed high-severity sink is safe.
   * **`REOPENED`**: A previously `FIXED` or `DISMISSED` vulnerability that reappeared in a subsequent `cm find` scan (critical regression signal — always alert the developer if `REOPENED` appears after patching!).
2. **Triage Integrity Mandate**: If a dynamic exploit script fails to execute or times out (e.g., due to `exebox` blocking TCP sockets or external toolchains), **retain the finding as `OPEN` (Unconfirmed) for manual review** — NEVER classify a failed dynamic PoC execution as a "False Positive".
3. **Source of Truth for Changes**: Diff scans don't update statuses in `.codemender/state.db`. To decide whether a change is clean, read the latest diff scan report (`.codemender/last-diff-scan.json` from `cm_diff_scan.sh`), not `cm report`.

---

## 2. Ground-Truth Finding JSON (`cm` v0.16.0)

`cm report -f json` outputs a bare JSON array of finding objects (or `null` when empty). A diff scan with `--format json --output <file>` writes the same objects (`[]` when clean). Below is a payload captured from `cm` v0.16.0 (`analysis` shortened):

```json
[
  {
    "finding_id": "3135aae9-a4f5-578c-b6e3-bb87ceea9a88",
    "session_id": "ChA2N2I4MjVjNWEyZDUzMzk5EAgaAjVmKgRtYWlu",
    "title": "SQL Injection in handle_order_status via orderId Parameter",
    "file_path": "/path/to/project/app/orders.py",
    "severity": "HIGH",
    "confidence": 100,
    "analysis": "- Source: The unauthenticated HTTP GET request query parameter 'orderId'...\n- Sink: ...conn.execute(f\"SELECT * FROM deliveries WHERE id = '{order_id}'\")...",
    "snippet": "def handle_order_status(params):\n    order_id = params.get(\"orderId\", \"\")\n    conn = get_connection()\n    rows = conn.execute(f\"SELECT * FROM deliveries WHERE id = '{order_id}'\").fetchall()\n    return str(rows)",
    "vuln_type": "CWE-89",
    "vuln_id": "CWE-89",
    "fingerprint": "0781e6430791ffc4",
    "status": "OPEN",
    "start_line": 4,
    "end_line": 8
  }
]
```

* **`status` values**: `"OPEN"`, `"VERIFIED"`, `"FIXED"`, `"DISMISSED"`, `"REOPENED"`. The `cm report --status` filter accepts only `OPEN`, `FIXED`, `DISMISSED`, and `REOPENED`, so select `VERIFIED` findings from this JSON.
* **`file_path`**: Absolute path. Convert it to a repository-relative path before showing it or comparing it with `git diff` output.
* **`finding_id`** and **`fingerprint`**: Stable identifiers. In cm 0.16.0 tests, a re-scan that reported the same issue at the same location kept both values even when the title was reworded. `finding_id` (or an unambiguous prefix) is the argument for `cm verify` and `cm fix`.
* **`vuln_id`** / **`vuln_type`**: The CWE identifier (e.g., `"CWE-89"`); older releases put the full CWE name in `vuln_type`.
* **`start_line` / `end_line`**: 1-indexed line range of the vulnerable code.
* **Diff scan titles**: Pre-existing findings in untouched code start with `[LEGACY / UNTOUCHED]` and never trigger `--fail-on`.

---

## 2b. Official `cm report import` Simple JSON Schema

When importing findings from external scanners via `cm report import -f findings.json`, use the official Simple JSON array schema (basic SARIF 2.1.0 is also supported on a best-effort basis). Pass `-p <project-dir>` when relative `file_path` values aren't relative to the current directory:

```json
[
  {
    "file_path": "src/auth/login.py",
    "line": 42,
    "title": "SQL Injection in login query",
    "message": "User input from request.args is concatenated directly into SQL execution.",
    "severity": "HIGH",
    "vuln_type": "CWE-89"
  }
]
```

---

## 3. Reading `PLAN.md` / `REPORT.md` / `info.yaml`

`PLAN.md` and `REPORT.md` contain the human-readable synthesis:
* **Vulnerability Description**: How untrusted source data reaches the sensitive sink.
* **Reproduction Steps**: Exact inputs used by the exploit script.
* **Impact Analysis**: What an attacker gains (e.g., data exfiltration, RCE, auth bypass).
* **Suggested Remediation**: Guidance to feed into `cm fix <finding-id> -c "<guidance>" --bypass-warning -y`.

`info.yaml` holds the machine-readable verdict (captured from `cm` v0.16.0):

```yaml
vulnerability_id: "CWE-89"
vulnerability_title: "SQL Injection in handle_order_status via orderId Parameter"
severity: "HIGH"
confidence: "certain"
status: "valid"
vulnerability_tags:
  - "SQL Injection"
  - "CWE-89"
chained_vulnerabilities: []
```

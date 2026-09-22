# CodeMender Exploit & Finding Format Reference

When `cm verify <finding-id>` executes, CodeMender writes investigation and exploit artifacts under `${PROJECT_ROOT}/.exploit/` (in `cm` v0.8.0, files such as `PLAN.md` and `LOG.md` are written directly to `.exploit/`, or under `.exploit/<finding-id>/` depending on the CLI topology).

> **Note on Sequential Verification**: Because `.exploit/PLAN.md` and `.exploit/LOG.md` may be overwritten across consecutive `cm verify` calls, inspect or archive them immediately after each verification run. Always ensure `.exploit/` is listed in `.git/info/exclude` so `cm fix` does not delete your verification artifacts.

## Artifact Directory Structure

```text
.exploit/                  (or .exploit/<finding-id>/)
├── PLAN.md                # Agent attack planning notes & target sink analysis
├── LOG.md                 # Execution logs and runtime sandbox stdout/stderr
├── poc.js / exploit.py    # Executable PoC script crafted by the verification agent
├── exploit.sh             # Bash runner script used in the sandbox
└── REPORT.md              # Root Cause Analysis and proof of exploit
```

---

## 1. Official 4-State Lifecycle & Triage Integrity (`OPEN`, `FIXED`, `DISMISSED`, `REOPENED`)

Before reporting a vulnerability to the user:
1. **Official Finding States (`status`)**:
   * **`OPEN`**: Detected (or imported) finding that is active (note: verified findings remain `OPEN` in `status` while `verified=1` is recorded in `.codemender/state.db`).
   * **`FIXED`**: Patch synthesized, applied, passed `build.command`, and verified against PoC re-attack.
   * **`DISMISSED`**: Marked by verification as a false positive, already mitigated, **or having insufficient confidence to confirm exploitability**. Because `DISMISSED` can also result from low verification confidence, still inspect the code context before assuming a dismissed high-severity sink is safe.
   * **`REOPENED`**: A previously `FIXED` or `DISMISSED` vulnerability that reappeared in a subsequent `cm find` scan (critical regression signal — always alert the developer if `REOPENED` appears after patching!).
2. **Triage Integrity Mandate**: If a dynamic exploit script fails to execute or times out (e.g., due to `exebox` blocking TCP sockets or external toolchains), **retain the finding as `OPEN` (Unconfirmed) for manual review** — NEVER classify a failed dynamic PoC execution as a "False Positive".

---

## 2. Ground-Truth `cm report -f json` Output (`cm` v0.8.0)

`cm report -f json` outputs a bare JSON array of finding objects (or `null` when empty). Below is an exact ground-truth payload captured from `cm` v0.8.0 after remediation:

```json
[
  {
    "finding_id": "7ca7fc35-3fb5-524c-b892-bcea593dd3a6",
    "session_id": "ChA1ZDlhNjU3YzRlMWNhOTNkEAgaATAqBG1haW4",
    "title": "SQL Injection in get_customer_orders via customer Query Parameter",
    "file_path": "/path/to/project/app.py",
    "severity": "HIGH",
    "confidence": 100,
    "analysis": "Source: Untrusted user input enters via HTTP GET parameter `customer`...\nSink: Interpolated into raw SQL query string using an f-string...",
    "snippet": "    query = f\"SELECT id, customer, item FROM orders WHERE customer = '{customer_name}'\"\n    cur.execute(query)",
    "vuln_type": "CWE-89: Improper Neutralization of Special Elements used in an SQL Command ('SQL Injection')",
    "vuln_id": "CWE-89",
    "status": "FIXED",
    "start_line": 23,
    "end_line": 24
  }
]
```

* **`status` values**: `"OPEN"`, `"FIXED"`, `"DISMISSED"`, `"REOPENED"`.
* **`vuln_id`**: Contains the CWE identifier (e.g., `"CWE-89"`).
* **`start_line` / `end_line`**: 1-indexed line range of the vulnerable sink.

---

## 2b. Official `cm report import` Simple JSON Schema

When importing findings from external scanners via `cm report import -f findings.json`, use the official Simple JSON array schema (basic SARIF 2.1.0 is also supported on a best-effort basis):

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

## 3. Reading `PLAN.md` / `REPORT.md`

`PLAN.md` and `REPORT.md` contain the human-readable synthesis:
* **Vulnerability Description**: How untrusted source data reaches the sensitive sink.
* **Reproduction Steps**: Exact inputs used by the exploit script.
* **Impact Analysis**: What an attacker gains (e.g., data exfiltration, RCE, auth bypass).
* **Suggested Remediation**: Guidance to feed into `cm fix <finding-id> -c "<guidance>" --bypass-warning -y`.

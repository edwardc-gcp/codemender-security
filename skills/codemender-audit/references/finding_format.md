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
├── info.yaml              # Optional machine-readable metadata
└── REPORT.md              # Root Cause Analysis and proof of exploit
```

---

## 1. Grounding Assessment & Triage Integrity (`VERIFIED` vs `UNCONFIRMED / OPEN`)

Before reporting a vulnerability to the user:
1. Check `cm report -f json` to see if the finding's `status` was updated to `VERIFIED` or `DISMISSED`.
2. Check if `.exploit/REPORT.md` or `.exploit/LOG.md` contains verifiable proof of exploit execution.
3. **Triage Integrity Mandate**: If the dynamic exploit script failed to execute or timed out (for example, because the `exebox` sandbox blocked local TCP socket binding or external toolchain execution like `~/.nvm` / `/opt/homebrew`), **classify the finding as `UNCONFIRMED / OPEN` for manual review**.
   * **NEVER** classify a failed dynamic PoC execution as a "False Positive". Only treat a finding as a False Positive when `cm verify` explicitly marks it `DISMISSED` with concrete code-level proof (e.g., parameterized query or unreachable dead code).

---

## 2. Reading `cm report -f json` & `info.yaml`

`cm report -f json` outputs a JSON array of finding objects:
```json
[
  {
    "finding_id": "7ca7fc35-e617-423b-be63-6dc25b1be578",
    "severity": "HIGH",
    "status": "OPEN",
    "patch_status": "PENDING",
    "file_path": "app.py",
    "line_number": 21,
    "cwe_id": "CWE-89",
    "title": "SQL Injection in get_customer_orders via Unsanitized String Formatting"
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

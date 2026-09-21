# CodeMender Exploit & Finding Format Reference

When `cm verify <finding-id>` executes, CodeMender creates an isolated investigation directory under `${PROJECT_ROOT}/.exploit/<finding-id>/`.

## Artifact Directory Structure

```text
.exploit/<finding-id>/
├── info.yaml          # Machine-readable metadata (severity, CWE, confidence)
├── PLAN.md            # Agent attack planning notes
├── LOG.md             # Execution logs and runtime stdout/stderr
├── poc.js             # Executable Node.js exploit (or exploit.py / exploit.sh)
├── exploit.sh         # Bash runner script used in the sandbox
└── REPORT.md          # Comprehensive Root Cause Analysis and proof of exploit
```

---

## 1. Grounding Assessment (Verified vs Unverified)

Before reporting a vulnerability to the user:
1. Check if `REPORT.md` exists and contains `Status: Confirmed` (or verifiable proof of execution).
2. Look at `LOG.md` to see if the HTTP response, process exit code, or leaked data was captured.
3. If the exploit script failed to trigger the defect, the finding is classified as **Unconfirmed / Potential False Positive**.

---

## 2. Reading `info.yaml`

Example:
```yaml
id: "find-9a8b7c6d"
cwe: "CWE-89"
title: "SQL Injection in User Authentication Handler"
severity: "CRITICAL"
confidence: 0.95
location:
  file: "src/auth/login.go"
  line_start: 45
  line_end: 48
verified: true
sandbox_exit_code: 0
```

---

## 3. Reading `REPORT.md`

`REPORT.md` contains the essential human-readable synthesis:
* **Vulnerability Description**: How untrusted source data reaches the sensitive sink.
* **Reproduction Steps**: Exact inputs used by the exploit script.
* **Impact Analysis**: What an attacker gains (e.g. data exfiltration, RCE, auth bypass).
* **Suggested Remediation**: Guidance to feed into `cm fix -c "<guidance>"`.

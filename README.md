# CodeMender Autonomous Security Skill (`/codemender-security`)

[![Skill: Antigravity](https://img.shields.io/badge/Antigravity-Skill-4285F4?style=flat&logo=google)](https://github.com/topics/antigravity-skill)
[![CLI: CodeMender](https://img.shields.io/badge/CodeMender_CLI-cm-34A853?style=flat)](https://cloud.google.com)
[![Platform: Google Cloud](https://img.shields.io/badge/Platform-Gemini_Enterprise-EA4335?style=flat&logo=googlecloud)](https://cloud.google.com)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

An autonomous AI Security Co-developer skill for **Google Antigravity** and the **Gemini Enterprise Agent Platform**, powered by the **CodeMender CLI (`cm`)**.

This skill empowers AI agents to autonomously discover AST/taint security vulnerabilities, synthesize and execute live exploit Proof-of-Concepts (PoCs), perform root-cause analysis (RCA), apply context-aware patches verified against local test suites, and generate enterprise compliance reports (SARIF/HTML).

---

## ⚡ Key Capabilities

```
┌────────────────────────────────────────────────────────────────────────┐
│                        CodeMender Workflow Loop                        │
├─────────────────┬─────────────────┬──────────────────┬─────────────────┤
│ 1. DISCOVER     │ 2. VERIFY (PoC) │ 3. REMEDIATE     │ 4. REPORT       │
│ cm find .       │ cm verify <id>  │ cm fix <id>      │ cm report       │
│ (AST & Taint)   │ (Live Exploit)  │ (Patch & Test)   │ (SARIF / HTML)  │
└─────────────────┴─────────────────┴──────────────────┴─────────────────┘
```

1. **AST & Taint Discovery (`cm find`)**: Fast, headless whole-codebase AST and taint analysis with severity prioritization.
2. **Autonomous Exploit Verification (`cm verify`)**: Synthesizes and runs dynamic PoC payloads under `.exploit/` (e.g. `poc.js`, `exploit.py`, `REPORT.md`) to eliminate false positives.
3. **Patch Synthesis & Regression Testing (`cm fix`)**: Synthesizes language-aware patches and automatically runs test suites (`npm test`, `pytest`, `cargo test`) to ensure zero regressions.
4. **Enterprise SARIF & HTML Reporting (`cm report`)**: Exports OASIS SARIF v2.1.0 for GitHub Advanced Security / CI/CD pipelines, or interactive standalone HTML dashboards.

---

## 📂 Repository Structure

```
.
├── SKILL.md                          # Primary agent skill definition and instructions
├── README.md                         # Repository documentation and setup guide
├── .gitignore                        # Standard ignore rules for temporary artifacts
├── references/                       # Deep reference documents
│   ├── cli_reference.md              # Advanced command catalog, session lifecycle, and error matrix
│   ├── config_schema.md              # Production schema for .codemender/config.yaml
│   └── vibe_coding_pitfalls.md       # Top GenAI & Vibe Coding security vulnerabilities
└── scripts/
    └── install_cm.sh                 # Cross-platform automated installer for the cm CLI binary
```

---

## 🚀 Installation & Quick Start

### 1. Install the Skill into Antigravity

Clone this repository into your global Antigravity skills directory or into your project workspace:

**Global (Recommended)**:
```bash
git clone https://github.com/edwardc-gcp/codemender-security.git ~/.gemini/config/skills/codemender-security
```

**Project-level (Workspace Specific)**:
```bash
git clone https://github.com/edwardc-gcp/codemender-security.git .agents/skills/codemender-security
```

### 2. Install the CodeMender CLI (`cm`)

Run the bundled cross-platform installer:

```bash
bash scripts/install_cm.sh
export PATH="$HOME/bin:$PATH"
```

Verify your environment:
```bash
cm --version
gcloud auth application-default print-access-token >/dev/null && echo "GCP ADC: OK"
```

---

## 🛠️ Usage Cheat Sheet

| Action | Command |
| :--- | :--- |
| **Scan Codebase** | `cm find . -y --unrestricted --model gemini-3.5-flash` |
| **Scan Uncommitted PR Diff** | `cm find . -y --diff-only --unrestricted` |
| **Verify Finding with Live PoC** | `cm verify <finding-id> --unrestricted --bypass-warning -y` |
| **Remediate with Guided Context** | `cm fix <finding-id> -c "Use parameterized queries" --unrestricted -y` |
| **Inspect Patch Diff** | `cm vcs diff` |
| **Rollback Broken Patch** | `cm vcs revert` |
| **Generate SARIF for CI/CD** | `cm report -f sarif > results.sarif` |
| **Generate HTML Dashboard** | `cm report -f html > report.html` |

---

## ⚙️ Configuration Schema

Configure workspace behavior in `.codemender/config.yaml`:

```yaml
version: 1
team_id: "secops-team"
model: gemini-3.5-flash

scan:
  extensions:
    include: [".py", ".java", ".go", ".js", ".ts", ".rs"]
    exclude: ["node_modules", ".git", "dist", "build"]
  incremental: true

build:
  command: "npm test" # Verified by `cm fix` before applying patches

vcs:
  type: "git"
```

For full options, see [Configuration Schema Reference](references/config_schema.md).

---

## 🛡️ License

Distributed under the Apache 2.0 License. See `LICENSE` for details.

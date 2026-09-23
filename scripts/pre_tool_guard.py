#!/usr/bin/env python3
"""Backward-compatible shim delegating to pure Bash scripts/pre_tool_guard.sh for live sessions."""
import os
os.execvp("bash", ["bash", "./scripts/pre_tool_guard.sh"])

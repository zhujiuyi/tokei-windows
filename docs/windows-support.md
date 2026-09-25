# Windows support status

The table tracks whether a data source has a Windows path in the collector and whether the Windows client has been verified with real Windows data. A code path alone does not count as a completed validation.

| Data source | Current Windows handling | Validation |
| --- | --- | --- |
| Claude Code | Local session logs and cache paths; CLI quota data where available | Needs real-log smoke test |
| Codex CLI | Session and archived session paths; local quota credentials/cache | Needs real-log and quota smoke test |
| Gemini / Antigravity | Local conversation paths and optional running localhost service | Needs real-log smoke test |
| Cursor, Zed, z.ai, Sub2API | Optional provider cards; API keys stored with the Windows credential store integration | Needs provider-by-provider validation |
| Qoder, QoderWork, Qoder CLI | Roaming/Local AppData discovery is present in upstream collector | Needs install-specific path validation |
| OpenCode, Devin, MiMoCode, Grok Bot | Windows AppData candidates are present in upstream collector | Needs current-client schema validation |
| Other CLI providers | Reuses upstream local log scanners and Python-standard-library parsing | Needs fixtures or real logs per tool |
| Git-based multi-device sync | Not yet integrated into the Windows client | Not available in this initial client |
| Windows login item | Current-user `Run` registry entry; removable from Settings | Windows 11 x64 smoke-tested |
| Windows keep-awake | `SetThreadExecutionState` while the client is running | Windows 11 x64 smoke-tested |
| Windows self-update | No self-updater or verified Windows release package is published yet | Not available |
| macOS Keychain / login item / IOKit features | Windows Credential Manager, startup item, and execution-state equivalents are used where implemented | macOS implementations are not used |

The standalone executable and its build configuration are verified on Windows 11 x64. Windows 10 and clean virtual-machine validation remain outstanding. Data-source rows marked as needing validation must not be treated as verified support, even if the upstream collector has a corresponding parser.

When a provider has no Windows client, local log, credentials, or compatible API, the UI should show unavailable status instead of displaying stale values as current.

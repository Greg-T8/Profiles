# AI commit messages

The shared prepare-commit-msg hook generates messages from staged changes using
an OpenAI-compatible Chat Completions API. It requires Git for Windows and
PowerShell 7 (pwsh) on PATH; no Copilot subscription, CLI, or SDK is needed.

## Setup

Choose a model offered by your provider and supply these variables to the process
that runs Git. For OpenRouter, use your OpenRouter API key and a model ID from its
catalog, such as the provider/model form. There is no default model.

Run in PowerShell, replacing the model placeholder:

~~~powershell
$env:AI_COMMIT_BASE_URL = 'https://openrouter.ai/api/v1'
$env:AI_COMMIT_MODEL = '<provider/model>'
$env:AI_COMMIT_API_KEY = Read-Host 'API key' -MaskInput
~~~

These assignments apply to this PowerShell session and its child processes.
For Git launched by an editor or another terminal, supply the same variables
through that application's environment and restart it after changing persistent
environment settings. Keep the key out of tracked files, profile source code,
command arguments, and Git configuration.

| Variable | Requirement |
| --- | --- |
| AI_COMMIT_BASE_URL | Optional; defaults to https://openrouter.ai/api/v1. HTTPS only; no embedded credentials, query, or fragment. |
| AI_COMMIT_MODEL | Required model ID supported by the selected endpoint. |
| AI_COMMIT_API_KEY | Required API key for the selected endpoint. |

The repository's Git/.gitconfig registers ~/.git-hooks as core.hooksPath.
On the current machine, that directory links to Git/.git-hooks here, so edits
take effect immediately. On another machine, install the existing link/config
before expecting the shared hook to run.

## Switch providers

Change the base URL, model, and key together. Supply the API base path only:
the generator appends /chat/completions. For example, Groq uses
https://api.groq.com/openai/v1 and its own model IDs and keys.

The endpoint must accept bearer authentication and a JSON request containing
model, stream: false, and messages, then return text in
choices[0].message.content. Provider-specific APIs and local-model setup are
outside this implementation.

## Behavior and troubleshooting

- Small commits send the full staged diff in a prompt of at most 24,000 characters.
  Larger commits send file statuses and change statistics bounded to 16,000
  characters. The selected service receives that content; these bounds are not
  secret redaction. Unstaged changes are not included.
- Messages request an imperative subject of at most 72 characters, without
  Conventional Commit prefixes, Markdown, commentary, or trailers.
- Requests have a 60-second HTTP timeout, zero automatic retries, and no redirects.
  Missing configuration, HTTP failures, and unusable responses abort the commit
  without overwriting the message file. Diagnostics omit keys and response bodies.
- The hook skips commits with a supplied Git message source (including explicit
  messages, merge, and reuse/amend sources) and skips repositories with no staged
  changes. It preserves the existing source-based guard.
- To provide your own message and bypass generation, use
  git commit -m "Describe your change". No API configuration is needed for that path.

For HTTP 401, check the key; for HTTP 429, check provider limits or credits.
For timeouts or other service errors, retry the commit yourself or supply a
manual message. No automatic fallback provider is selected.

Provider references:
[OpenRouter](https://openrouter.ai/docs/quickstart) and
[Groq compatibility](https://console.groq.com/docs/openai).

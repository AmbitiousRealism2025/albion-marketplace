# GLM-5.2 Run Config Notes

## Z.AI standard API, hard agentic task

```json
{
  "model": "glm-5.2",
  "messages": [],
  "thinking": { "type": "enabled" },
  "reasoning_effort": "max",
  "stream": true,
  "tool_stream": true,
  "clear_thinking": false,
  "max_tokens": 65536
}
```

Use `clear_thinking: false` only when the harness can preserve prior `reasoning_content` blocks exactly, privately, and in order.

## Z.AI standard API, medium task

```json
{
  "model": "glm-5.2",
  "messages": [],
  "thinking": { "type": "enabled" },
  "reasoning_effort": "high",
  "stream": true,
  "max_tokens": 32768
}
```

## Quick task

```json
{
  "model": "glm-5.2",
  "messages": [],
  "thinking": { "type": "disabled" },
  "stream": true,
  "max_tokens": 4096
}
```

Use only for trivial tasks where the skill should not activate.

## Together AI note

Together's GLM-5.2 endpoint documents streaming tool calls without a separate `tool_stream` parameter. Use provider-specific docs rather than copying Z.AI parameters blindly.

## Safety note

Do not include secrets, credentials, private keys, or sensitive logs in persistent workbench files. Redact before saving evidence.

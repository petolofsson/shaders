# How to Create and Update Scheduled Research Jobs

## Tools

Use the `RemoteTrigger` tool (deferred — load with `ToolSearch` first):

```
ToolSearch: select:RemoteTrigger
```

Actions: `list`, `get`, `create`, `update`, `run`

---

## Listing / inspecting existing triggers

```
RemoteTrigger { action: "list" }
RemoteTrigger { action: "get", trigger_id: "trig_..." }
```

Known triggers as of 2026-05-03:

| Name | ID | Schedule |
|------|----|----------|
| R86 Research Job | trig_01BpXuTwojGbEKDqF7SN7VBj | `7 */6 * * *` |
| (other nightly jobs) | see list | `0 4 * * *` |

---

## Updating an existing trigger's prompt

This is the normal path — **do not use the web UI**. The update API accepts partial
updates; only send what needs to change.

```json
RemoteTrigger {
  "action": "update",
  "trigger_id": "trig_...",
  "body": {
    "job_config": {
      "ccr": {
        "environment_id": "env_01F9ZEcuFEYLy12V3x4qCxDu",
        "events": [{
          "data": {
            "message": {
              "content": "...full prompt text...",
              "role": "user"
            },
            "parent_tool_use_id": null,
            "session_id": "",
            "type": "user",
            "uuid": "...keep original uuid from get response..."
          }
        }],
        "session_context": { ...keep original from get response... }
      }
    }
  }
}
```

**Important:** always `get` the trigger first and copy `uuid`, `environment_id`, and
`session_context` verbatim — don't invent values.

---

## Creating a new trigger

The create API is finicky about the event format. The reliable pattern (verified):

```json
RemoteTrigger {
  "action": "create",
  "body": {
    "name": "My Job Name",
    "cron_expression": "7 */6 * * *",
    "enabled": true,
    "job_config": {
      "ccr": {
        "environment_id": "env_01F9ZEcuFEYLy12V3x4qCxDu",
        "events": [{
          "data": {
            "message": {
              "content": "...prompt...",
              "role": "user"
            },
            "parent_tool_use_id": null,
            "session_id": "",
            "type": "user",
            "uuid": "generate-a-uuid-here"
          }
        }],
        "session_context": {
          "allowed_tools": ["Bash"],
          "autofix_on_pr_create": false,
          "model": "claude-sonnet-4-6",
          "outcomes": [{
            "git_repository": {
              "git_info": {
                "branches": ["claude/some-branch-name"],
                "repo": "petolofsson/shaders"
              }
            }
          }],
          "sources": [{
            "git_repository": {
              "url": "https://github.com/petolofsson/shaders"
            }
          }]
        }
      }
    }
  }
}
```

If create fails with event format errors, create the trigger via the claude.ai/code
Routines UI and then update it with the correct prompt using the update action above.

---

## Brave search in RemoteTrigger jobs

MCP tools are **not available** in CCR/Routine sessions — only `Bash` is allowed.
Use curl for web search:

```bash
curl -s "https://api.search.brave.com/res/v1/web/search?q=QUERY&count=5" \
  -H "X-Subscription-Token: $BRAVE_API_KEY" \
  -H "Accept: application/json"
```

Session-based CronCreate jobs can use `mcp__brave-search__brave_web_search` directly.

---

## R-number computation in job prompts

Always fetch and checkout `alpha` **before** computing the next R-number, or the CCR
session (which starts on `main`) will see an outdated file list:

```bash
git -C /home/pol/code/shaders fetch origin alpha
git -C /home/pol/code/shaders checkout alpha
ls /home/pol/code/shaders/research/R*.md | grep -oP 'R\K[0-9]+' | sort -n | tail -1
```

Then add 1 to that number for the output filename.

---

## Job definition files

Each job has a definition file in this directory (`research/jobs/job_*.md`).
Keep the definition file and the Routine prompt in sync — use the update action
to push changes rather than editing via the web UI.

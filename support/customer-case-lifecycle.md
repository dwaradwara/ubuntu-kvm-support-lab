# Customer Case Lifecycle

This guide converts technical troubleshooting into explicit support-case ownership.

## 1. Qualify the case

Record customer-visible symptom, affected systems/users, start time and timezone, severity/business impact, recent changes, environment/Ubuntu release, reproducibility, and workaround status.

Severity should be tied to customer impact and the applicable support policy, not to how technically interesting the issue is.

## 2. Acknowledge and set the next checkpoint

A useful first response should:

- confirm the impact you understood
- state what evidence is being collected
- request only information that changes the investigation
- provide a concrete next-update checkpoint when continued investigation is required
- avoid promising a fix time that engineering has not committed to

## 3. Establish a baseline

Capture known-good or expected state before making changes:

- package/service versions
- service state
- resource state
- relevant networking
- recent package/configuration changes
- logs around the first failure

## 4. Isolate the failing layer

Work from evidence:

`customer symptom -> application -> service/process -> dependency -> OS/package -> kernel/network/storage`

State which hypotheses were ruled out and how.

## 5. Mitigate safely

Separate:

- **workaround** — restores service without removing the underlying defect
- **remediation** — removes the identified cause
- **permanent product fix** — may require engineering/package release work

A rollback can be an appropriate workaround while a permanent update is evaluated.

## 6. Escalate with a complete handoff

Engineering should not have to ask for basic reproduction information already available to support.

Include exact versions/builds, reproduction steps, expected vs actual result, logs/backtrace, timeline, impact, mitigation result, and a minimal reproducer when possible.

## 7. Maintain customer updates

Each update should clearly separate:

**Confirmed** — what the evidence establishes.

**Working hypothesis** — what is plausible but not yet proven.

**Action** — what support or engineering is doing next.

**Customer action** — only what the customer actually needs to do.

**Next checkpoint** — when another update will be provided, if applicable.

## 8. Validate resolution

Do not close on "service started." Validate the original customer path and any important dependency chain.

## 9. Close with reusable knowledge

Capture root cause, fix/workaround, validation, prevention, knowledge-base candidate, and engineering/documentation follow-up.

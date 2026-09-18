# Canonical Gap Closure v2

This workstream extends the existing Ubuntu/KVM support lab only where the Associate Linux Support Engineer role still benefits from stronger evidence.

It deliberately avoids creating another large platform project.

## Objectives

1. Demonstrate explicit crash-dump and stack-trace troubleshooting on Ubuntu.
2. Demonstrate package-regression investigation, rollback, escalation, and customer expectation-setting.
3. Add support-facing artifacts for case ownership, technical notices, and engineering escalation.
4. Build practical knowledge of the Ubuntu package/update lifecycle and Stable Release Update (SRU) process.
5. Keep all claims evidence-based: incident reports are not marked complete until commands are executed and outputs are captured.

## Planned additions

### INC017 — systemd service crash and core-dump backtrace

Evidence target:

`systemd failure -> journalctl -> coredumpctl -> gdb backtrace -> root cause -> fix -> successful restart -> clean validation`

### INC018 — package regression and support escalation

Evidence target:

`healthy package -> controlled bad upgrade -> service failure -> package provenance -> dpkg history -> rollback -> hold/workaround -> customer update -> engineering escalation -> validation`

This is a controlled local package simulation. It is not presented as an actual Ubuntu archive regression.

## Support artifacts

- `support/customer-case-lifecycle.md`
- `support/technical-notice-template.md`
- `support/engineering-escalation-template.md`
- `docs/ubuntu-development-support-guide.md`

## Completion criteria

An incident is complete only when the repository contains:

- baseline evidence
- failure evidence
- diagnostic commands and outputs
- root-cause statement supported by evidence
- remediation
- recovery validation
- customer-facing update
- engineering escalation when appropriate
- cleanup steps

Do not replace observed output with invented examples in final incident reports.

# Target Architecture
Status: CONFIRMED

## Goal
“Tek hedefim ... uygulamanın en üstte çıkması” (user, 16.10.2026). Build KamuBul into the most useful, reliable and discoverable Turkish public-job app through evidence-led competitor research, product quality and measured improvements. Rankings and download leadership are goals, never guarantees.

## Target State
### Product and growth
- Research competitors, user needs, Play policy and search intent; retain sourced findings and a handoff-ready strategy in `docs/growth/`.
- Keep the app useful and trustworthy: accurate official listings, clear eligibility unknowns, working saved searches/notifications, understandable subscription and accessible flows.
- Measure listing and product changes against real baselines when enough data exists; no automatic recurring monitoring until explicitly requested.

## Non-Goals
- Store operations are executed with the release tooling, but their state is recorded for handoff in `docs/RELEASES.md` and tracked as tasks (user request, 25.10.2026).
- Guaranteed first place, installs or search ranking; automatic heartbeat/cron monitoring.

## Open Decisions
- None blocking this migration. Product trade-offs belong in future tasks/ADRs.

## Success Conditions
- Active non-publishing product/research work is tracked as executable Brain tasks.
- Current architecture and key accepted constraints reflect the repository, not stale tracker claims.
- The retired tracker has no runtime, state or pointer left in the project.

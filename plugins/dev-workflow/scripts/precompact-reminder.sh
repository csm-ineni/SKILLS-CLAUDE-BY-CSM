#!/usr/bin/env bash
# PreCompact hook: remind the agent to persist progress before context compaction.
echo "dev-workflow: context is about to be compacted. If .claude/PROGRESS.md is stale, update it NOW (current task, done, next concrete step, open questions, active branch) so nothing is lost."
exit 0

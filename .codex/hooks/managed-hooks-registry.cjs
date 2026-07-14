'use strict';

const MANAGED_HOOKS = [
  'gsd-check-update-worker.js',
  'gsd-check-update.js',
  'gsd-config-reload.js',
  'gsd-context-monitor.js',
  'gsd-cursor-post-tool.js',
  'gsd-cursor-session-start.js',
  'gsd-ensure-canonical-path.js',
  'gsd-graphify-update.sh',
  'gsd-phase-boundary.sh',
  'gsd-prompt-guard.js',
  'gsd-read-guard.js',
  'gsd-read-injection-scanner.js',
  'gsd-session-state.sh',
  'gsd-statusline.js',
  'gsd-update-banner.js',
  'gsd-validate-commit.sh',
  'gsd-workflow-guard.js',
  'gsd-worktree-path-guard.js',
];

module.exports = { MANAGED_HOOKS };

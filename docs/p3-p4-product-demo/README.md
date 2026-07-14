# P3/P4 Product & Demo Workspace

This branch contains the non-technical preparation, visual-quality, test-evidence, and demo materials for ReRoom.

## Scope

This workspace supports the controlled chair/small-table hero demo. It does not authorize product implementation, infrastructure changes, deployment, or changes to the canonical product decisions.

## Shared working structure

Keep working material in the team's shared drive using these folders:

```text
01_demo-room
02_furniture-assets
03_user-flow-and-script
04_test-checklists
05_visual-review
06_screenshots-and-video
07_final-submission
```

Only approved, non-sensitive summaries should be added to this branch. Do not upload raw room footage, participant names, consent forms, credentials, or personal data to GitHub.

## Responsibilities

### P3 — product story and visual quality

- Prepare the controlled demo room and half-circle walkthrough path.
- Curate the replacement-furniture shortlist and identify hero and backup assets.
- Maintain the demo script and visual acceptance checklist.
- Review whether selection, readiness, placement, replacement, restore, and replay are understandable.

### P4 — test evidence and human review

- Prepare the tester note, consent process, feedback form, and build-test log.
- Create annotated target screenshots from the approved demo room.
- Organize the five-person visual review for removal when a stable build is available.
- Collect reproducible feedback, screenshots, and short issue reports.

## Working sequence

1. Complete room setup, asset shortlist, demo script, test forms, and annotated target frames in parallel.
2. When developers provide a build, run the standard device test and log evidence.
3. Turn every issue into a reproducible report with steps, expected result, actual result, and a screenshot or timestamp.
4. Run human visual review only on a stable removal build.
5. Rehearse the full demo five times before recording final material.

## Standard issue report

```text
Title:
Build/version:
Device and room:
Steps:
Expected:
Actual:
Evidence link and timestamp:
Severity: blocks demo / noticeable / minor
```

## Definition of ready

The P3/P4 preparation is ready when:

- the room, walkthrough route, and hero object are approved;
- a hero replacement and backup are documented;
- the demo script and test checklist are complete;
- testers can submit structured feedback;
- evidence is stored safely outside GitHub and linked from summaries when needed.

## Safety and accuracy

Do not describe prerecorded replay as live. Do not claim arbitrary object removal, LiDAR dependence, or features that have not passed the relevant test. If removal does not pass the visual review, the demo should focus on replacement and replay.

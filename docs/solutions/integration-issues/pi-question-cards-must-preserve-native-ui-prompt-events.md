---
title: Preserve native UI prompt events when replacing Pi question dialogs
date: 2026-10-26
category: integration-issues
module: dotfiles/pi/extensions/question.ts
problem_type: architecture_pattern
component: tooling
severity: medium
tags: [pi, question, tuios, native-ui, inbox]
applies_when:
  - "Replacing a native selector with a custom inline question card"
  - "Checking whether Tuios recognizes a pane as needing user input"
---

# Preserve native UI prompt events when replacing Pi question dialogs

## Context

A question card can look correct and still fail to put its pane in Tuios's Inbox.
Keeping a tool invocation pending is not the integration contract: Tuios listens
for Pi's native UI prompt lifecycle, not the tool's name or its visual contents.

## Guidance

- Await `ctx.ui.custom` for the TUI card, rather than displaying a widget and
  waiting on an independent promise. Pi's `ExtensionRunner.wrapUIPromptContext`
  wraps the native custom UI in `ui_prompt_start` / `ui_prompt_end` events with
  kind `custom`. The inspected Tuios Pi integration classifies that kind as a
  question requiring input; `confirm` is classified separately as approval.
- Keep native `ctx.ui.select` / `ctx.ui.input` as the RPC fallback. Do not assume
  that a client which supports blocking dialogs can render a custom TUI component.
- Return answers through the tool result and its structured details, not through
  an additional global event carrying user text. The lifecycle needs only its
  blocking state, not a copy of the answer.

`dotfiles/pi/extensions/question.ts` owns this boundary; the card's presentation
is separate in `dotfiles/pi/extensions/question-ui.ts`.

## Verification and applicability

Component tests prove editing and selection behavior, but a mocked `ui.custom`
callback does not prove Inbox integration. Exercise a real Pi prompt and observe
the paired native events, including cancellation. This change was verified with
real keyboard and mouse interaction and `custom` start/end events for each prompt.

Keep this distinction when replacing any blocking question UI: visual presence
and native attention signaling are separate acceptance checks.

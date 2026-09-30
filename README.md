# CodexMeter

A lightweight native macOS menu bar app for monitoring your Codex usage.

CodexMeter keeps the important numbers visible without turning into a full-blown management tool. Check your 5-hour and 7-day usage limits at a glance, inspect token consumption, estimate API-equivalent costs, and see your daily usage trends.

## Features

### Usage Limits

Monitor Codex usage limits directly from the macOS menu bar.

- 5-hour usage limit
- 7-day usage limit
- Remaining quota
- Reset time
- Automatic refresh
- Manual refresh

The menu bar uses two compact circular indicators:

- 🔴 Red — used quota
- 🟢 Green — remaining quota

Conceptually:

`◉ 5h   ◉ 7d`

The amount of red and green in each ring represents the current usage ratio.

### Token Usage

Track Codex token consumption locally.

CodexMeter shows:

- Input tokens
- Cached input tokens
- Output tokens
- Total tokens
- Today's usage
- 7 / 14 / 30 day usage

Token history is collected from local Codex session data.

### Estimated Cost

Estimate the API-equivalent cost of your Codex usage based on model pricing.

Cost calculations take into account:

- Input tokens
- Cached input tokens
- Output tokens
- Model-specific pricing

> Estimated cost is an API-equivalent estimate and does not represent the actual cost of a ChatGPT or Codex subscription.

### Daily Usage Chart

Visualize token usage with a simple daily bar chart.

Available ranges:

- 7 days
- 14 days
- 30 days

Hover over a day to inspect its token usage and estimated cost.

## Design

CodexMeter is intentionally small and focused.

The goal is not to replace Codex or become another multi-provider AI dashboard.

It answers four simple questions:

**How much Codex quota do I have left?**

**How many tokens am I using?**

**What would those tokens cost at API pricing?**

**How has my usage changed over the last few days?**

## Tech Stack

CodexMeter is a native macOS application.

- Swift
- SwiftUI
- Swift Charts
- macOS MenuBarExtra
- URLSession
- Codable

No Electron.

No web frontend.

No backend service.

No database.

## Data Sources

### Usage Limits

5-hour and 7-day Codex usage limits are retrieved through the local Codex integration.

The application should prefer the Codex app-server / usage mechanism rather than relying exclusively on rate-limit information stored in session files.

### Token History

Token usage is derived from local Codex session data, including:

`~/.codex/sessions`

and, where applicable:

`~/.codex/archived_sessions`

CodexMeter parses token usage events and aggregates them by day.

All token-history processing is performed locally.

## Privacy

CodexMeter is designed to keep usage analysis local.

It does not require its own backend and does not upload your Codex session history to a third-party analytics service.

## Planned V1

The initial version focuses on:

- [ ] 5-hour usage indicator
- [ ] 7-day usage indicator
- [ ] Circular menu bar indicators
- [ ] Usage reset countdown
- [ ] Automatic refresh
- [ ] Manual refresh
- [ ] Today's token usage
- [ ] Input / cached input / output token breakdown
- [ ] Estimated API cost
- [ ] Daily token usage chart
- [ ] 7 / 14 / 30 day views
- [ ] Period token totals
- [ ] Period estimated costs
- [ ] Launch at login

## Philosophy

CodexBar is a powerful Swiss Army knife.

CodexMeter aims to be the dashboard on the wall.

Open it, understand your usage, and get back to coding.

## Status

🚧 Early development

CodexMeter is currently being built as a lightweight native macOS utility.

## License

License to be determined.

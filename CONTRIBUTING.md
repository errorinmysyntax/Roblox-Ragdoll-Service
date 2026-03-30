# Contributing

Thanks for helping improve SimpleRagdollService.

## Development

- Keep changes focused and backwards-compatible where practical.
- Prefer small PRs with a clear explanation and a short reproduction clip/steps for gameplay changes.

## Testing checklist (manual)

- Verify on both R6 and R15.
- Ragdoll → recover repeatedly (no accumulating constraints/attachments).
- Verify tools/hotbar behavior if you change script disabling / hotbar locking.
- Verify behavior with accessories and layered clothing.

## Style

- Use idiomatic Luau.
- Keep public API stable (`new`, `Ragdoll`, `Unragdoll`, `Toggle`, `IsRagdolled`).

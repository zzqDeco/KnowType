# InputCommitResultPolicy

## Responsibility

`InputCommitResultPolicy` centralizes commit results for raw input, prefix
candidates, segment candidates, continuation candidates, and punctuation.

## Boundaries

- It decides commit semantics, not AppKit insertion mechanics.
- Host write operations stay in `InputControllerCoordinator` and client seams.

## Behavior Notes

- `Space` commits a visible full prefix or applies a selected segment.
- `Return` commits raw composition.
- `Tab` commits prefix plus continuation only when the prefix is fully resolved.
- Punctuation commits composition plus mapped punctuation or inserts directly
  when no composition exists.

## Tests

- `InputCommitResultPolicyTests`
- `InputSessionControllerTests`
- `InputControllerCoordinatorTests`

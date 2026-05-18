# InputCandidateListBuilder

## Responsibility

`InputCandidateListBuilder` maps suggestion snapshots and composition state into
candidate rows available to the input method UI.

## Boundaries

- It builds input-method candidate lists; it does not perform correction or
  provider calls.
- Visual styling stays in panel renderer and AppKit views.

## Behavior Notes

- Prefix candidates remain separate from continuation candidates.
- Segment candidates apply to raw ranges inside the active composition.
- Raw input is visible only when no suggestion row exists.
- When provider-backed continuation is pending, hidden local fallback
  continuations must not appear as configured AI output.

## Tests

- `InputCandidateListBuilderTests`
- `CandidatePanelRendererTests`
- `InputControllerCoordinatorTests`

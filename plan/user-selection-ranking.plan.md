# User Selection Ranking

Goal: make local candidate ranking adapt to recent user prefix choices without uploading selection data or importing external dictionaries.

Implementation:

- use the existing `InputContext.userSelectionHistory` field as a local-only ranking signal
- boost generated prefix candidates whose text appears in recent selection history
- cap the boost so history can reorder plausible local candidates without manufacturing candidates that the engine did not generate
- keep Level 0 protected input unchanged and provider-free
- keep an in-memory selection history in the IMK controller and pass a snapshot to immediate local suggestions and async provider-backed suggestions
- learn selected prefix text from Space, Tab, native candidate selection, and numeric prefix shortcuts when the committed result starts with that prefix

Validation:

- `fangan` defaults to `方案`
- `fangan` with recent `方法` selection history ranks `方法` first while keeping `方案` available
- `InputSessionController.update` forwards selection history into the suggestion loader
- `swift test --filter CorrectionEngineTests`
- `swift test --filter InputSessionControllerTests`
- `swift test`
- `git diff --check`

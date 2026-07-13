# ProcessInputModeStateRuntime

## Responsibility

`ProcessInputModeStateRuntime` provides the thread-safe host-lifetime instance
of `InputModeStateMachine` shared by all production IMK coordinators.

## Boundaries

- The runtime serializes snapshot reads and pure transitions with a lock; it
  does not execute UI, host-write, Rime, or persistence side effects.
- `KnowTypeInputController` owns the production singleton and injects it.
- Each coordinator owns its derived quote and symbol-candidate state and reacts
  to generation changes on the next input turn.

## Behavior Notes

- App, window, and input-session changes do not create or reload mode state.
- Coordinators synchronize each new generation to the live Rime session options;
  the process runtime itself remains free of Rime side effects.
- A fresh host process creates a fresh linked Chinese state using the saved
  global symbol width.
- The runtime tracks the last observed configured width separately from the
  current width. A real Settings change updates current state once, while a new
  coordinator observing the same configuration cannot erase a temporary
  `Shift + Space` change.
- Tests may inject isolated or explicitly shared instances to avoid global
  cross-test state.

## Tests

- `ProcessInputModeStateRuntimeTests`
- `InputControllerCoordinatorTests`

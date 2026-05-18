# Sources/KnowTypeSettingsUI

`KnowTypeSettingsUI` owns the reusable SwiftUI settings surface.

It is intentionally separate from `KnowTypeSettingsApp` so the standalone settings app, `KnowType.prefPane`, and the InputMethodKit preferences window all render the same controls and use the same stores.

Current settings cover:

- input mode defaults and input scheme;
- candidate page size and panel layout preference;
- local lexicon status and recommended lexicon installation;
- provider profile editing and connection diagnostics;
- AI continuation enablement, length, and candidate count;
- privacy/status copy and local install diagnostics.

The module persists user choices through shared `com.knowtype.preferences` defaults and provider/secret stores. It does not import `KnowTypeInputMethod`.

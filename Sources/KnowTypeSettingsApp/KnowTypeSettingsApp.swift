import KnowTypeProviders
import SwiftUI

@main
struct KnowTypeSettingsApp: App {
    @StateObject private var viewModel: ProviderProfilesViewModel

    init() {
        let model: ProviderProfilesViewModel
        do {
            model = try ProviderProfilesViewModel()
        } catch {
            model = ProviderProfilesViewModel(
                profileStore: FailingProviderProfileStore(errorDescription: error.localizedDescription),
                secretStore: InMemorySecretStore()
            )
        }
        _viewModel = StateObject(wrappedValue: model)
    }

    var body: some Scene {
        WindowGroup("KnowType Settings") {
            ProviderProfilesView(viewModel: viewModel)
                .frame(minWidth: 840, minHeight: 560)
        }
    }
}

private struct FailingProviderProfileStore: ProviderProfileStore {
    let errorDescription: String

    func loadProfiles() throws -> ProviderProfilesFile {
        throw FailingProviderProfileStoreError(description: errorDescription)
    }

    func saveProfiles(_ profiles: ProviderProfilesFile) throws {
        throw FailingProviderProfileStoreError(description: errorDescription)
    }
}

private struct FailingProviderProfileStoreError: Error, CustomStringConvertible {
    let description: String
}

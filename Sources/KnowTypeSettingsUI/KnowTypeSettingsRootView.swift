import KnowTypeProviders
import SwiftUI

public struct KnowTypeSettingsRootView: View {
    @StateObject private var viewModel: ProviderProfilesViewModel
    @StateObject private var runtimePreferencesViewModel: RuntimePreferencesViewModel

    public init(
        viewModel: ProviderProfilesViewModel? = nil,
        runtimePreferencesViewModel: RuntimePreferencesViewModel = RuntimePreferencesViewModel()
    ) {
        _viewModel = StateObject(wrappedValue: viewModel ?? Self.makeProviderProfilesViewModel())
        _runtimePreferencesViewModel = StateObject(wrappedValue: runtimePreferencesViewModel)
    }

    public var body: some View {
        ProviderProfilesView(
            viewModel: viewModel,
            runtimePreferencesViewModel: runtimePreferencesViewModel
        )
    }

    private static func makeProviderProfilesViewModel() -> ProviderProfilesViewModel {
        do {
            return try ProviderProfilesViewModel()
        } catch {
            return ProviderProfilesViewModel(
                profileStore: FailingProviderProfileStore(errorDescription: error.localizedDescription),
                secretStore: InMemorySecretStore()
            )
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

struct FailingProviderProfileStoreError: Error, CustomStringConvertible, LocalizedError {
    let description: String

    var errorDescription: String? {
        description
    }
}

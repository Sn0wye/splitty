import Foundation

enum AvatarUploadStage: String, CaseIterable, Equatable {
    case preparing
    case uploading
    case confirming
}

enum AvatarUploadState: Equatable {
    case idle
    case inProgress(AvatarUploadStage)
    case done
    case failed(AvatarUploadStage, String)
}

@MainActor
struct ProfileDataSource {
    var update: (ProfileUpdate) async throws -> User
    var createAvatarUpload: () async throws -> AvatarUpload
    var uploadAvatar: (Data, AvatarUpload) async throws -> Void
    var prepareAvatar: (Data, AvatarCrop) throws -> Data

    static let live = ProfileDataSource(
        update: ProfileService.shared.update,
        createAvatarUpload: ProfileService.shared.createAvatarUpload,
        uploadAvatar: ProfileService.shared.uploadAvatar,
        prepareAvatar: AvatarImageProcessor.prepare
    )
}

@MainActor
final class ProfileViewModel: ObservableObject {
    static let nameLimit = 60

    @Published var name: String {
        didSet {
            if name.count > Self.nameLimit {
                name = String(name.prefix(Self.nameLimit))
            }
        }
    }
    @Published private(set) var user: User
    @Published private(set) var uploadState: AvatarUploadState = .idle
    @Published private(set) var isSaving = false
    @Published private(set) var isRemovingAvatar = false
    @Published var errorMessage: String?

    private let dataSource: ProfileDataSource
    private let applyUser: (User) -> Void
    private var savedName: String
    private var retryInput: (Data, AvatarCrop)?

    init(
        user: User,
        dataSource: ProfileDataSource = .live,
        applyUser: ((User) -> Void)? = nil
    ) {
        self.user = user
        name = user.name
        savedName = user.name
        self.dataSource = dataSource
        self.applyUser = applyUser ?? { AuthenticationManager.shared.updateCurrentUser($0) }
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nameLength: Int { name.count }

    var hasUnsavedChanges: Bool {
        trimmedName != savedName
    }

    var canSave: Bool {
        !isBusy && !trimmedName.isEmpty && trimmedName != savedName
    }

    var canRetryUpload: Bool {
        if case .failed = uploadState { return retryInput != nil }
        return false
    }

    var isUploadingAvatar: Bool {
        if case .inProgress = uploadState { return true }
        return false
    }

    var isChangingAvatar: Bool { isUploadingAvatar || isRemovingAvatar }
    var canChangeAvatar: Bool { !isBusy }

    private var isBusy: Bool {
        isSaving || isChangingAvatar
    }

    func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            apply(try await dataSource.update(ProfileUpdate(name: trimmedName)))
            name = user.name
            savedName = user.name
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.displayMessage
        }
    }

    func uploadAvatar(_ sourceData: Data, crop: AvatarCrop) async {
        guard !isBusy else { return }
        retryInput = (sourceData, crop)
        errorMessage = nil
        var stage = AvatarUploadStage.preparing

        do {
            uploadState = .inProgress(.preparing)
            let data = try dataSource.prepareAvatar(sourceData, crop)
            let slot = try await dataSource.createAvatarUpload()

            stage = .uploading
            uploadState = .inProgress(.uploading)
            try await dataSource.uploadAvatar(data, slot)

            stage = .confirming
            uploadState = .inProgress(.confirming)
            let updated = try await dataSource.update(ProfileUpdate(avatarKey: .set(slot.key)))
            apply(updated)
            retryInput = nil
            uploadState = .done
        } catch where error.isCancellation {
            uploadState = .idle
        } catch {
            uploadState = .failed(stage, error.displayMessage)
        }
    }

    func retryUpload() async {
        guard let retryInput else { return }
        await uploadAvatar(retryInput.0, crop: retryInput.1)
    }

    func removeAvatar() async {
        guard !isBusy else { return }
        isRemovingAvatar = true
        errorMessage = nil
        defer { isRemovingAvatar = false }

        do {
            apply(try await dataSource.update(ProfileUpdate(avatarKey: .remove)))
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.displayMessage
        }
    }

    private func apply(_ updatedUser: User) {
        user = updatedUser
        applyUser(updatedUser)
    }
}

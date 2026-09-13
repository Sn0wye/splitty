import Foundation
import Testing
import UIKit
@testable import Splitty

@MainActor
struct ProfileViewModelTests {
    @Test func saveGateRequiresAChangedValidNameAndClosesDuringSave() async {
        var viewModel: ProfileViewModel!
        let source = ProfileDataSource(
            update: { update in
                #expect(viewModel.canSave == false)
                return Self.updatedUser(name: update.name ?? "Gabriel")
            },
            createAvatarUpload: { Self.slot },
            uploadAvatar: { _, _ in },
            prepareAvatar: { _, _ in Data() }
        )
        viewModel = ProfileViewModel(user: Self.user, dataSource: source)

        #expect(viewModel.canSave == false)
        viewModel.name = "   "
        #expect(viewModel.canSave == false)
        viewModel.name = "Gabriel Snow"
        #expect(viewModel.canSave)

        await viewModel.save()

        #expect(viewModel.canSave == false)
        #expect(viewModel.name == "Gabriel Snow")
    }

    @Test func trimsTheSavedNameAndCapsTypingAtSixtyCharacters() async {
        var submittedName: String?
        let source = ProfileDataSource(
            update: { update in
                submittedName = update.name
                return Self.updatedUser(name: update.name ?? "Gabriel")
            },
            createAvatarUpload: { Self.slot },
            uploadAvatar: { _, _ in },
            prepareAvatar: { _, _ in Data() }
        )
        let viewModel = ProfileViewModel(user: Self.user, dataSource: source)

        viewModel.name = String(repeating: "a", count: 60) + "   "
        #expect(viewModel.name.count == 60)
        await viewModel.save()

        #expect(submittedName == String(repeating: "a", count: 60))
    }

    @Test func unsavedChangesTrackTheNameDraft() {
        let viewModel = ProfileViewModel(user: Self.user, dataSource: .unused)

        #expect(!viewModel.hasUnsavedChanges)
        viewModel.name = "Gabriel Snow"
        #expect(viewModel.hasUnsavedChanges)
        viewModel.name = "Gabriel"
        #expect(!viewModel.hasUnsavedChanges)
        viewModel.name = "  Gabriel  "
        #expect(!viewModel.hasUnsavedChanges)
    }

    @Test func mapsTheProfileResponseWithoutWeakeningUserDecoding() throws {
        let payload = #"{"id":1,"name":"Gabriel","email":"gabriel@example.com","avatarUrl":"https://img.example/avatar.jpg"}"#

        let profile = try JSONDecoder().decode(ProfileResponse.self, from: Data(payload.utf8))
        let user = profile.user

        #expect(user.name == "Gabriel")
        #expect(user.createdAt.isEmpty)
        #expect(user.updatedAt.isEmpty)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(User.self, from: Data(payload.utf8))
        }
    }

    @Test func staleMemberDisplayResolvesFromTheSignedInUser() {
        let member = GroupMember(
            id: 4,
            userId: Self.user.id,
            name: "Old name",
            email: Self.user.email,
            avatarUrl: "https://img.example/old.jpg"
        )
        let updatedUser = Self.updatedUser(
            name: "Gabriel Snow",
            avatarURL: URL(string: "https://img.example/new.jpg")
        )

        let display = MemberDisplay(member).resolved(currentUser: updatedUser)

        #expect(display.name == "Gabriel Snow")
        #expect(display.avatarURL == URL(string: "https://img.example/new.jpg"))
    }

    @Test func applyingASaveUpdatesAuthenticationManagersCurrentUser() async {
        let manager = AuthenticationManager(source: ProfileAuthenticationSource())
        manager.login(user: Self.user)
        let source = ProfileDataSource(
            update: { update in Self.updatedUser(name: update.name ?? "Gabriel") },
            createAvatarUpload: { Self.slot },
            uploadAvatar: { _, _ in },
            prepareAvatar: { _, _ in Data() }
        )
        let viewModel = ProfileViewModel(user: Self.user, dataSource: source, applyUser: manager.updateCurrentUser)
        viewModel.name = "Gabriel Snow"

        await viewModel.save()

        #expect(manager.currentUser?.name == "Gabriel Snow")
    }

    @Test func uploadMovesThroughEveryStageAndUpdatesTheSignedInUser() async {
        var viewModel: ProfileViewModel!
        var appliedUser: User?
        let source = ProfileDataSource(
            update: { update in
                #expect(viewModel.uploadState == .inProgress(.confirming))
                #expect(update.avatarKey == .set("avatars/1/photo.jpg"))
                return Self.updatedUser(name: "Gabriel", avatarURL: URL(string: "https://img.example/photo.jpg"))
            },
            createAvatarUpload: {
                #expect(viewModel.uploadState == .inProgress(.preparing))
                return Self.slot
            },
            uploadAvatar: { data, slot in
                #expect(viewModel.uploadState == .inProgress(.uploading))
                #expect(data == Data([1, 2, 3]))
                #expect(slot == Self.slot)
            },
            prepareAvatar: { _, _ in
                #expect(viewModel.uploadState == .inProgress(.preparing))
                return Data([1, 2, 3])
            }
        )
        viewModel = ProfileViewModel(user: Self.user, dataSource: source) { appliedUser = $0 }

        await viewModel.uploadAvatar(Data([9]), crop: .fullImage)

        #expect(viewModel.uploadState == .done)
        #expect(viewModel.user.avatarURL == URL(string: "https://img.example/photo.jpg"))
        #expect(appliedUser?.avatarURL == viewModel.user.avatarURL)
    }

    @Test(arguments: AvatarUploadStage.allCases)
    func aFailureAtEveryUploadStepCanBeRetried(stage: AvatarUploadStage) async {
        var shouldFail = true
        let source = ProfileDataSource(
            update: { _ in
                if stage == .confirming, shouldFail { throw ProfileTestError.failed }
                return Self.updatedUser(name: "Gabriel")
            },
            createAvatarUpload: {
                if stage == .preparing, shouldFail { throw ProfileTestError.failed }
                return Self.slot
            },
            uploadAvatar: { _, _ in
                if stage == .uploading, shouldFail { throw ProfileTestError.failed }
            },
            prepareAvatar: { _, _ in Data([1]) }
        )
        let viewModel = ProfileViewModel(user: Self.user, dataSource: source)

        await viewModel.uploadAvatar(Data([9]), crop: .fullImage)
        #expect(viewModel.uploadState == .failed(stage, "Upload failed"))
        #expect(viewModel.canRetryUpload)

        shouldFail = false
        await viewModel.retryUpload()
        #expect(viewModel.uploadState == .done)
    }

    @Test func removingAnAvatarSendsAnExplicitNullAndUpdatesTheSignedInUser() async {
        var requestBody: [String: Any] = [:]
        var appliedUser: User?
        let source = ProfileDataSource(
            update: { update in
                requestBody = update.body
                return Self.updatedUser(name: "Gabriel", avatarURL: URL(string: "https://dicebear.example/fallback.png"))
            },
            createAvatarUpload: { Self.slot },
            uploadAvatar: { _, _ in },
            prepareAvatar: { _, _ in Data() }
        )
        let viewModel = ProfileViewModel(user: Self.user, dataSource: source) { appliedUser = $0 }

        await viewModel.removeAvatar()

        #expect(requestBody.keys.sorted() == ["avatarKey"])
        #expect(requestBody["avatarKey"] is NSNull)
        #expect(appliedUser?.avatarURL == URL(string: "https://dicebear.example/fallback.png"))
    }

    fileprivate static let user = User(
        id: 1,
        name: "Gabriel",
        email: "gabriel@example.com",
        avatarURL: URL(string: "https://img.example/old.jpg"),
        createdAt: "",
        updatedAt: ""
    )

    fileprivate static let slot = AvatarUpload(
        key: "avatars/1/photo.jpg",
        uploadURL: URL(string: "https://storage.example/upload")!,
        contentType: "image/jpeg",
        maxBytes: 2_000_000
    )

    private static func updatedUser(name: String, avatarURL: URL? = nil) -> User {
        User(
            id: 1,
            name: name,
            email: "gabriel@example.com",
            avatarURL: avatarURL,
            createdAt: "",
            updatedAt: ""
        )
    }
}

private enum ProfileTestError: LocalizedError {
    case failed

    var errorDescription: String? { "Upload failed" }
}

@MainActor
private struct ProfileAuthenticationSource: AuthenticationSource {
    func isAuthenticated() -> Bool { true }
    func currentUser() async throws -> User { ProfileViewModelTests.user }
}

private extension ProfileDataSource {
    static let unused = ProfileDataSource(
        update: { _ in ProfileViewModelTests.user },
        createAvatarUpload: { ProfileViewModelTests.slot },
        uploadAvatar: { _, _ in },
        prepareAvatar: { _, _ in Data() }
    )
}

using System.Net;
using System.Net.Http.Json;
using System.Text.Json;

namespace Splitty.API.Tests;

[Collection(nameof(ApiCollection))]
public sealed class ProfileTests : IDisposable
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };

    private readonly ApiFactory _factory;
    private readonly FakeAvatarStorage _storage;

    public ProfileTests(ApiFactory factory)
    {
        _factory = factory;
        _storage = factory.AvatarStorage;
        _storage.Reset();
    }

    public void Dispose() => _storage.Reset();

    [Fact]
    public async Task Own_profile_returns_the_signed_in_user()
    {
        var user = await ApiClient.Create(_factory).SignInAsync(name: "Ada");
        var client = ApiClient.Create(_factory, user.Token);

        var profile = await ReadProfileAsync(client.GetProfileAsync());

        Assert.Equal(user.Id, profile.Id);
        Assert.Equal("Ada", profile.Name);
        Assert.Equal(user.Email, profile.Email);
    }

    [Fact]
    public async Task The_removed_auth_profile_route_is_gone()
    {
        var user = await ApiClient.Create(_factory).SignInAsync();
        var client = ApiClient.Create(_factory, user.Token);

        var response = await client.Http.GetAsync("/auth");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task Unauthenticated_profile_read_is_401()
    {
        var response = await ApiClient.Create(_factory).GetProfileAsync();

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // Avatar resolution.

    [Fact]
    public async Task A_user_with_no_provider_picture_gets_a_generated_one_seeded_on_their_id()
    {
        var user = await ApiClient.Create(_factory).SignInAsync();
        var client = ApiClient.Create(_factory, user.Token);

        var profile = await ReadProfileAsync(client.GetProfileAsync());

        Assert.Contains("api.dicebear.com", profile.AvatarUrl);
        Assert.Contains($"seed={user.Id}", profile.AvatarUrl);
        // Never the email: the seed is rendered verbatim in every peer's client.
        Assert.DoesNotContain(user.Email, profile.AvatarUrl);
    }

    [Fact]
    public async Task A_provider_picture_wins_over_the_generated_one()
    {
        var user = await ApiClient.Create(_factory).SignInAsync(picture: "https://provider.test/ada.jpg");
        var client = ApiClient.Create(_factory, user.Token);

        var profile = await ReadProfileAsync(client.GetProfileAsync());

        Assert.Equal("https://provider.test/ada.jpg", profile.AvatarUrl);
    }

    [Fact]
    public async Task An_uploaded_image_wins_over_the_provider_picture()
    {
        var user = await ApiClient.Create(_factory).SignInAsync(picture: "https://provider.test/ada.jpg");
        var client = ApiClient.Create(_factory, user.Token);

        var key = await UploadAsync(client);
        var profile = await ReadProfileAsync(client.UpdateProfileAsync(new { avatarKey = key }));

        Assert.Equal($"{FakeAvatarStorage.PublicBase}/{key}", profile.AvatarUrl);
    }

    [Fact]
    public async Task Clearing_the_avatar_falls_back_to_the_provider_picture()
    {
        var user = await ApiClient.Create(_factory).SignInAsync(picture: "https://provider.test/ada.jpg");
        var client = ApiClient.Create(_factory, user.Token);

        var key = await UploadAsync(client);
        (await client.UpdateProfileAsync(new { avatarKey = key })).EnsureSuccessStatusCode();

        var profile = await ReadProfileAsync(client.UpdateProfileRawAsync("""{"avatarKey":null}"""));

        Assert.Equal("https://provider.test/ada.jpg", profile.AvatarUrl);
    }

    [Fact]
    public async Task Clearing_the_avatar_with_no_provider_picture_falls_back_to_the_generated_one()
    {
        var user = await ApiClient.Create(_factory).SignInAsync();
        var client = ApiClient.Create(_factory, user.Token);

        var key = await UploadAsync(client);
        (await client.UpdateProfileAsync(new { avatarKey = key })).EnsureSuccessStatusCode();

        var profile = await ReadProfileAsync(client.UpdateProfileRawAsync("""{"avatarKey":null}"""));

        Assert.Contains($"seed={user.Id}", profile.AvatarUrl);
    }

    // Upload and commit.

    [Fact]
    public async Task An_upload_url_is_pinned_to_a_content_type_and_a_size_limit()
    {
        var user = await ApiClient.Create(_factory).SignInAsync();
        var client = ApiClient.Create(_factory, user.Token);

        var response = await client.CreateAvatarUploadAsync();
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
        Assert.StartsWith($"avatars/{user.Id}/", body.GetProperty("key").GetString());
        Assert.NotEmpty(body.GetProperty("uploadUrl").GetString()!);
        Assert.Equal("image/jpeg", body.GetProperty("contentType").GetString());
        Assert.Equal(2 * 1024 * 1024, body.GetProperty("maxBytes").GetInt64());
    }

    [Fact]
    public async Task Committing_a_key_whose_object_does_not_exist_is_refused()
    {
        var user = await ApiClient.Create(_factory).SignInAsync();
        var client = ApiClient.Create(_factory, user.Token);

        // Presigned, but the client never completed the PUT.
        var upload = await client.CreateAvatarUploadAsync();
        var key = (await upload.Content.ReadFromJsonAsync<JsonElement>(Json)).GetProperty("key").GetString()!;

        var response = await client.UpdateProfileAsync(new { avatarKey = key });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Contains("api.dicebear.com", (await ReadProfileAsync(client.GetProfileAsync())).AvatarUrl);
    }

    [Fact]
    public async Task Committing_a_key_issued_to_someone_else_is_refused()
    {
        var owner = await ApiClient.Create(_factory).SignInAsync();
        var ownerClient = ApiClient.Create(_factory, owner.Token);
        var key = await UploadAsync(ownerClient);

        var stranger = await ApiClient.Create(_factory).SignInAsync();
        var strangerClient = ApiClient.Create(_factory, stranger.Token);

        var response = await strangerClient.UpdateProfileAsync(new { avatarKey = key });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task An_object_over_the_size_limit_is_refused_and_discarded()
    {
        var user = await ApiClient.Create(_factory).SignInAsync();
        var client = ApiClient.Create(_factory, user.Token);

        var key = await UploadAsync(client, contentLength: 3 * 1024 * 1024);

        var response = await client.UpdateProfileAsync(new { avatarKey = key });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Contains(key, _storage.Deleted);
    }

    [Fact]
    public async Task An_object_of_the_wrong_content_type_is_refused()
    {
        var user = await ApiClient.Create(_factory).SignInAsync();
        var client = ApiClient.Create(_factory, user.Token);

        var key = await UploadAsync(client, contentType: "video/mp4");

        var response = await client.UpdateProfileAsync(new { avatarKey = key });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Replacing_an_avatar_deletes_the_previous_object()
    {
        var user = await ApiClient.Create(_factory).SignInAsync();
        var client = ApiClient.Create(_factory, user.Token);

        var first = await UploadAsync(client);
        (await client.UpdateProfileAsync(new { avatarKey = first })).EnsureSuccessStatusCode();

        var second = await UploadAsync(client);
        var profile = await ReadProfileAsync(client.UpdateProfileAsync(new { avatarKey = second }));

        Assert.Contains(first, _storage.Deleted);
        Assert.DoesNotContain(second, _storage.Deleted);
        Assert.Equal($"{FakeAvatarStorage.PublicBase}/{second}", profile.AvatarUrl);
    }

    [Fact]
    public async Task A_failed_cleanup_does_not_fail_the_request()
    {
        var user = await ApiClient.Create(_factory).SignInAsync();
        var client = ApiClient.Create(_factory, user.Token);

        var first = await UploadAsync(client);
        (await client.UpdateProfileAsync(new { avatarKey = first })).EnsureSuccessStatusCode();

        var second = await UploadAsync(client);
        _storage.FailDeletes = true;

        var profile = await ReadProfileAsync(client.UpdateProfileAsync(new { avatarKey = second }));

        Assert.Equal($"{FakeAvatarStorage.PublicBase}/{second}", profile.AvatarUrl);
    }

    // Name.

    [Fact]
    public async Task A_name_change_survives_a_subsequent_sign_in()
    {
        var subject = Guid.NewGuid().ToString("N");
        var email = $"{Guid.NewGuid():N}@splitty.test";

        var user = await ApiClient.Create(_factory).SignInAsync(email, name: "Provider Name", subject: subject);
        var client = ApiClient.Create(_factory, user.Token);

        (await client.UpdateProfileAsync(new { name = "Chosen Name" })).EnsureSuccessStatusCode();

        // The same Google identity signs in again, still carrying the provider's name.
        var again = await ApiClient.Create(_factory).SignInAsync(email, name: "Provider Name", subject: subject);
        Assert.Equal(user.Id, again.Id);

        var profile = await ReadProfileAsync(ApiClient.Create(_factory, again.Token).GetProfileAsync());

        Assert.Equal("Chosen Name", profile.Name);
    }

    [Fact]
    public async Task A_name_is_trimmed()
    {
        var user = await ApiClient.Create(_factory).SignInAsync();
        var client = ApiClient.Create(_factory, user.Token);

        var profile = await ReadProfileAsync(client.UpdateProfileAsync(new { name = "  Ada Lovelace  " }));

        Assert.Equal("Ada Lovelace", profile.Name);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public async Task An_empty_name_is_refused(string name)
    {
        var user = await ApiClient.Create(_factory).SignInAsync(name: "Ada");
        var client = ApiClient.Create(_factory, user.Token);

        var response = await client.UpdateProfileAsync(new { name });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("Ada", (await ReadProfileAsync(client.GetProfileAsync())).Name);
    }

    [Fact]
    public async Task A_name_over_sixty_characters_is_refused()
    {
        var user = await ApiClient.Create(_factory).SignInAsync();
        var client = ApiClient.Create(_factory, user.Token);

        var response = await client.UpdateProfileAsync(new { name = new string('a', 61) });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task An_omitted_field_is_left_alone()
    {
        var user = await ApiClient.Create(_factory).SignInAsync(name: "Ada");
        var client = ApiClient.Create(_factory, user.Token);

        var key = await UploadAsync(client);
        (await client.UpdateProfileAsync(new { avatarKey = key })).EnsureSuccessStatusCode();

        // Names only. The avatar is not in the body, so it must not be cleared.
        var profile = await ReadProfileAsync(client.UpdateProfileRawAsync("""{"name":"Grace"}"""));

        Assert.Equal("Grace", profile.Name);
        Assert.Equal($"{FakeAvatarStorage.PublicBase}/{key}", profile.AvatarUrl);
        Assert.DoesNotContain(key, _storage.Deleted);
    }

    // Peer reads.

    [Fact]
    public async Task A_peer_sharing_a_group_is_readable()
    {
        var group = await GroupFixture.CreateAsync(_factory);

        var profile = await ReadProfileAsync(group.Owner.GetPeerProfileAsync(group.GuestId));

        Assert.Equal(group.GuestId, profile.Id);
        Assert.Equal("Guest", profile.Name);
        Assert.NotEmpty(profile.Email);
    }

    [Fact]
    public async Task A_stranger_is_a_404()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        var stranger = await ApiClient.Create(_factory).SignInAsync(name: "Stranger");

        var response = await group.Owner.GetPeerProfileAsync(stranger.Id);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task A_user_left_alone_in_no_shared_group_stops_being_readable()
    {
        var group = await GroupFixture.CreateAsync(_factory);

        (await group.Guest.LeaveGroupAsync(group.Id)).EnsureSuccessStatusCode();

        Assert.Equal(HttpStatusCode.NotFound, (await group.Owner.GetPeerProfileAsync(group.GuestId)).StatusCode);
    }

    [Fact]
    public async Task The_caller_can_read_their_own_id_through_the_peer_route()
    {
        var user = await ApiClient.Create(_factory).SignInAsync();
        var client = ApiClient.Create(_factory, user.Token);

        var profile = await ReadProfileAsync(client.GetPeerProfileAsync(user.Id));

        Assert.Equal(user.Id, profile.Id);
    }

    // The same resolution behind the endpoints that already carried an avatar.

    [Fact]
    public async Task A_member_row_carries_the_resolved_avatar()
    {
        var group = await GroupFixture.CreateAsync(_factory);

        var key = await UploadAsync(group.Guest);
        (await group.Guest.UpdateProfileAsync(new { avatarKey = key })).EnsureSuccessStatusCode();

        var body = await group.Owner.ReadJsonAsync(await group.Owner.GetGroupAsync(group.Id));
        var members = body.GetProperty("members").EnumerateArray().ToList();

        var guest = members.Single(m => m.GetProperty("userId").GetInt32() == group.GuestId);
        Assert.Equal($"{FakeAvatarStorage.PublicBase}/{key}", guest.GetProperty("avatarUrl").GetString());

        // The owner never uploaded and has no provider picture, so the row that used to be
        // an empty string is now a generated image.
        var owner = members.Single(m => m.GetProperty("userId").GetInt32() == group.OwnerId);
        Assert.Contains($"seed={group.OwnerId}", owner.GetProperty("avatarUrl").GetString()!);
    }

    [Fact]
    public async Task A_peer_row_carries_the_resolved_avatar()
    {
        var group = await GroupFixture.CreateAsync(_factory);
        await _factory.DrainProcessedAsync();

        var body = await group.Owner.ReadJsonAsync(await group.Owner.GetPeopleAsync());
        var peer = body.GetProperty("peers").EnumerateArray().Single();

        Assert.Contains($"seed={group.GuestId}", peer.GetProperty("avatarUrl").GetString()!);
    }

    private async Task<string> UploadAsync(ApiClient client, long contentLength = 60_000, string? contentType = null)
    {
        var response = await client.CreateAvatarUploadAsync();
        response.EnsureSuccessStatusCode();

        var key = (await response.Content.ReadFromJsonAsync<JsonElement>(Json)).GetProperty("key").GetString()!;
        _storage.PutObject(key, contentLength, contentType);

        return key;
    }

    private static async Task<ProfileSnapshot> ReadProfileAsync(Task<HttpResponseMessage> request)
    {
        var response = await request;
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);

        return new ProfileSnapshot(
            body.GetProperty("id").GetInt32(),
            body.GetProperty("name").GetString()!,
            body.GetProperty("email").GetString()!,
            body.GetProperty("avatarUrl").GetString()!);
    }

    private sealed record ProfileSnapshot(int Id, string Name, string Email, string AvatarUrl);
}

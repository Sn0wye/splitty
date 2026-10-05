using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;

namespace Splitty.API.Tests;

/// <summary>
/// Deactivation switches an account off and keeps everything; deletion turns the user into
/// a `[removed]` tombstone that keeps only what the group's money still needs.
/// </summary>
[Collection(nameof(ApiCollection))]
public sealed class AccountClosureTests : IDisposable
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };

    private readonly ApiFactory _factory;
    private readonly FakeAvatarStorage _storage;

    public AccountClosureTests(ApiFactory factory)
    {
        _factory = factory;
        _storage = factory.AvatarStorage;
        _storage.Reset();
    }

    public void Dispose() => _storage.Reset();

    // Deactivation.

    [Fact]
    public async Task Deactivating_revokes_the_token_on_every_route()
    {
        var user = await ApiClient.Create(_factory).SignInAsync();
        var client = ApiClient.Create(_factory, user.Token);
        var groupId = await client.CreateGroupAsync();

        Assert.Equal(HttpStatusCode.NoContent, (await client.DeactivateAccountAsync()).StatusCode);

        await ErrorResponseAssertions.AssertErrorAsync(await client.GetGroupAsync(groupId), HttpStatusCode.Unauthorized);
        await ErrorResponseAssertions.AssertErrorAsync(await client.GetProfileAsync(), HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Signing_in_again_reactivates_the_same_user_with_everything_intact()
    {
        var pair = await PairWhereGuestOwesAsync(10m);
        var oldGuest = ApiClient.Create(_factory, pair.Guest.Token);

        (await oldGuest.DeactivateAccountAsync()).EnsureSuccessStatusCode();

        var again = await ApiClient.Create(_factory)
            .SignInAsync(pair.Guest.Email, pair.Guest.Name, pair.GuestSubject);
        var guest = ApiClient.Create(_factory, again.Token);

        Assert.Equal(pair.Guest.Id, again.Id);
        var group = await guest.ReadJsonAsync(await guest.GetGroupAsync(pair.GroupId));
        Assert.Equal(-10m, group.GetProperty("netBalance").GetDecimal());
        Assert.Equal("Guest", (await ReadProfileAsync(guest.GetProfileAsync())).Name);

        // Reactivation issues a new session; it does not bring the old ones back.
        await ErrorResponseAssertions.AssertErrorAsync(await oldGuest.GetProfileAsync(), HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Linking_by_verified_email_also_reactivates()
    {
        var user = await ApiClient.Create(_factory).SignInAsync(name: "Ada");
        (await ApiClient.Create(_factory, user.Token).DeactivateAccountAsync()).EnsureSuccessStatusCode();

        // A new subject with the same verified address links to the deactivated user.
        var again = await ApiClient.Create(_factory).SignInAsync(user.Email, "Ada");

        Assert.Equal(user.Id, again.Id);
        (await ApiClient.Create(_factory, again.Token).GetProfileAsync()).EnsureSuccessStatusCode();
    }

    [Fact]
    public async Task A_deactivated_member_still_looks_and_behaves_like_a_member()
    {
        var pair = await PairWhereGuestOwesAsync(10m);
        (await ApiClient.Create(_factory, pair.Guest.Token).DeactivateAccountAsync()).EnsureSuccessStatusCode();

        var group = await pair.OwnerClient.ReadJsonAsync(await pair.OwnerClient.GetGroupAsync(pair.GroupId));
        var member = MemberOf(group, pair.Guest.Id);
        Assert.Equal("Guest", member.GetProperty("name").GetString());
        Assert.Equal(pair.Guest.Email, member.GetProperty("email").GetString());

        var paidByGuest = await pair.OwnerClient.CreateExpenseAsync(pair.GroupId,
            ExpenseBody(paidBy: pair.Guest.Id, pair.Owner.Id, pair.Guest.Id));
        Assert.Equal(HttpStatusCode.OK, paidByGuest.StatusCode);
    }

    // Deletion.

    [Fact]
    public async Task Deleting_revokes_the_token_and_strips_the_personal_data_co_members_see()
    {
        var pair = await PairWhereGuestOwesAsync(10m);
        var guest = ApiClient.Create(_factory, pair.Guest.Token);

        Assert.Equal(HttpStatusCode.NoContent, (await guest.DeleteAccountAsync()).StatusCode);

        await ErrorResponseAssertions.AssertErrorAsync(await guest.GetProfileAsync(), HttpStatusCode.Unauthorized);

        var profile = await ReadProfileAsync(pair.OwnerClient.GetPeerProfileAsync(pair.Guest.Id));
        Assert.Equal("[removed]", profile.Name);
        Assert.Equal(string.Empty, profile.Email);
        Assert.DoesNotContain("provider.test", profile.AvatarUrl);

        Assert.Equal(0, await _factory.UseDbAsync(db => db.OAuthAccount.CountAsync(a => a.UserId == pair.Guest.Id)));
        Assert.Equal(string.Empty, await _factory.UseDbAsync(db =>
            db.User.Where(u => u.Id == pair.Guest.Id).Select(u => u.Email).SingleAsync()));
    }

    [Fact]
    public async Task Signing_in_after_deleting_creates_a_fresh_user_with_the_same_email()
    {
        var subject = Guid.NewGuid().ToString("N");
        var user = await ApiClient.Create(_factory).SignInAsync(name: "Ada", subject: subject);
        var client = ApiClient.Create(_factory, user.Token);
        await client.CreateGroupAsync();

        (await client.DeleteAccountAsync()).EnsureSuccessStatusCode();

        var again = await ApiClient.Create(_factory).SignInAsync(user.Email, "Ada", subject);
        var fresh = ApiClient.Create(_factory, again.Token);

        Assert.NotEqual(user.Id, again.Id);
        Assert.Equal(user.Email, (await ReadProfileAsync(fresh.GetProfileAsync())).Email);
        var groups = await fresh.ReadJsonAsync(await fresh.Http.GetAsync("/group"));
        Assert.Equal(0, groups.GetArrayLength());
    }

    [Fact]
    public async Task A_settled_member_who_deletes_leaves_the_member_list()
    {
        var pair = await PairAsync();

        (await ApiClient.Create(_factory, pair.Guest.Token).DeleteAccountAsync()).EnsureSuccessStatusCode();

        var group = await pair.OwnerClient.ReadJsonAsync(await pair.OwnerClient.GetGroupAsync(pair.GroupId));
        Assert.DoesNotContain(Members(group), m => m.GetProperty("userId").GetInt32() == pair.Guest.Id);
    }

    [Fact]
    public async Task An_unsettled_member_who_deletes_stays_as_a_tombstone_carrying_the_balance()
    {
        var pair = await PairWhereGuestOwesAsync(10m);

        (await ApiClient.Create(_factory, pair.Guest.Token).DeleteAccountAsync()).EnsureSuccessStatusCode();

        var group = await pair.OwnerClient.ReadJsonAsync(await pair.OwnerClient.GetGroupAsync(pair.GroupId));
        Assert.Equal("[removed]", MemberOf(group, pair.Guest.Id).GetProperty("name").GetString());
        Assert.Equal(10m, group.GetProperty("netBalance").GetDecimal());

        // The tombstone's debt is the other side of the owner's credit: the group still sums to zero.
        var summary = await pair.OwnerClient.ReadSummaryAsync(pair.GroupId);
        Assert.Equal(10m, summary.AmountOwedBy(pair.Owner.Id, pair.Guest.Id));
    }

    [Fact]
    public async Task A_debtor_can_still_settle_with_a_deleted_creditor_and_then_remove_them()
    {
        var pair = await PairWhereGuestOwesAsync(10m);

        (await pair.OwnerClient.DeleteAccountAsync()).EnsureSuccessStatusCode();

        var settle = await pair.GuestClient.SettleUpAsync(pair.GroupId, new { withUserId = pair.Owner.Id, amount = 10m });
        Assert.Equal(HttpStatusCode.OK, settle.StatusCode);
        await _factory.WaitForProcessedAsync();

        Assert.Equal(HttpStatusCode.NoContent,
            (await pair.GuestClient.RemoveMemberAsync(pair.GroupId, pair.Owner.Id)).StatusCode);
        var group = await pair.GuestClient.ReadJsonAsync(await pair.GuestClient.GetGroupAsync(pair.GroupId));
        Assert.DoesNotContain(Members(group), m => m.GetProperty("userId").GetInt32() == pair.Owner.Id);
    }

    [Fact]
    public async Task A_tombstone_cannot_be_the_payer_or_a_participant_of_a_new_expense()
    {
        var pair = await PairWhereGuestOwesAsync(10m);

        (await pair.GuestClient.DeleteAccountAsync()).EnsureSuccessStatusCode();

        var asPayer = await pair.OwnerClient.CreateExpenseAsync(pair.GroupId,
            ExpenseBody(paidBy: pair.Guest.Id, pair.Owner.Id));
        var asParticipant = await pair.OwnerClient.CreateExpenseAsync(pair.GroupId,
            ExpenseBody(paidBy: pair.Owner.Id, pair.Owner.Id, pair.Guest.Id));

        await ErrorResponseAssertions.AssertErrorAsync(asPayer, HttpStatusCode.Forbidden);
        await ErrorResponseAssertions.AssertErrorAsync(asParticipant, HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task A_deleted_peer_with_a_balance_shows_as_removed_in_people()
    {
        var pair = await PairWhereGuestOwesAsync(10m);

        (await pair.GuestClient.DeleteAccountAsync()).EnsureSuccessStatusCode();

        var people = await pair.OwnerClient.ReadJsonAsync(await pair.OwnerClient.GetPeopleAsync());
        var peer = people.GetProperty("peers").EnumerateArray().Single();
        Assert.Equal("[removed]", peer.GetProperty("name").GetString());
    }

    [Fact]
    public async Task The_sole_member_deleting_deletes_the_group()
    {
        var user = await ApiClient.Create(_factory).SignInAsync();
        var client = ApiClient.Create(_factory, user.Token);
        var groupId = await client.CreateGroupAsync();

        (await client.DeleteAccountAsync()).EnsureSuccessStatusCode();

        Assert.False(await GroupExistsAsync(groupId));
    }

    [Fact]
    public async Task A_group_left_with_only_tombstones_is_deleted()
    {
        var pair = await PairWhereGuestOwesAsync(10m);

        (await pair.GuestClient.DeleteAccountAsync()).EnsureSuccessStatusCode();
        Assert.True(await GroupExistsAsync(pair.GroupId));

        (await pair.OwnerClient.DeleteAccountAsync()).EnsureSuccessStatusCode();
        Assert.False(await GroupExistsAsync(pair.GroupId));
    }

    [Fact]
    public async Task The_last_live_member_leaving_deletes_a_group_of_tombstones()
    {
        var pair = await PairWhereGuestOwesAsync(10m);
        var third = await ApiClient.Create(_factory).SignInAsync(name: "Third");
        var thirdClient = ApiClient.Create(_factory, third.Token);
        (await thirdClient.AcceptInviteAsync(await pair.OwnerClient.CreateInviteAsync(pair.GroupId)))
            .EnsureSuccessStatusCode();

        // Both keep their memberships: one owes the other.
        (await pair.GuestClient.DeleteAccountAsync()).EnsureSuccessStatusCode();
        (await pair.OwnerClient.DeleteAccountAsync()).EnsureSuccessStatusCode();
        Assert.True(await GroupExistsAsync(pair.GroupId));

        Assert.Equal(HttpStatusCode.NoContent, (await thirdClient.LeaveGroupAsync(pair.GroupId)).StatusCode);
        Assert.False(await GroupExistsAsync(pair.GroupId));
    }

    [Fact]
    public async Task Deleting_removes_every_avatar_object_including_uncommitted_uploads()
    {
        var user = await ApiClient.Create(_factory).SignInAsync();
        var client = ApiClient.Create(_factory, user.Token);
        var committed = await UploadAsync(client);
        (await client.UpdateProfileAsync(new { avatarKey = committed })).EnsureSuccessStatusCode();
        var abandoned = await UploadAsync(client);

        var stranger = await ApiClient.Create(_factory).SignInAsync();
        var strangers = await UploadAsync(ApiClient.Create(_factory, stranger.Token));

        (await client.DeleteAccountAsync()).EnsureSuccessStatusCode();

        Assert.False(_storage.Contains(committed));
        Assert.False(_storage.Contains(abandoned));
        Assert.True(_storage.Contains(strangers));
    }

    [Fact]
    public async Task Deleting_succeeds_when_avatar_cleanup_fails()
    {
        var user = await ApiClient.Create(_factory).SignInAsync();
        var client = ApiClient.Create(_factory, user.Token);
        var key = await UploadAsync(client);
        _storage.FailDeletes = true;

        Assert.Equal(HttpStatusCode.NoContent, (await client.DeleteAccountAsync()).StatusCode);

        Assert.True(_storage.Contains(key));
        await ErrorResponseAssertions.AssertErrorAsync(await client.GetProfileAsync(), HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Renaming_to_the_tombstone_name_is_refused()
    {
        var user = await ApiClient.Create(_factory).SignInAsync();
        var client = ApiClient.Create(_factory, user.Token);

        var response = await client.UpdateProfileAsync(new { name = " [removed] " });

        await ErrorResponseAssertions.AssertErrorAsync(response, HttpStatusCode.BadRequest);
    }

    // Helpers.

    private sealed record Pair(
        int GroupId,
        SignedInUser Owner,
        ApiClient OwnerClient,
        SignedInUser Guest,
        string GuestSubject,
        ApiClient GuestClient);

    /// Two members and no money, with the guest's subject kept so a test can sign them in again.
    private async Task<Pair> PairAsync()
    {
        var owner = await ApiClient.Create(_factory).SignInAsync(name: "Owner", picture: "https://provider.test/o.jpg");
        var ownerClient = ApiClient.Create(_factory, owner.Token);
        var groupId = await ownerClient.CreateGroupAsync();
        var code = await ownerClient.CreateInviteAsync(groupId);

        var guestSubject = Guid.NewGuid().ToString("N");
        var guest = await ApiClient.Create(_factory)
            .SignInAsync(name: "Guest", subject: guestSubject, picture: "https://provider.test/g.jpg");
        var guestClient = ApiClient.Create(_factory, guest.Token);
        (await guestClient.AcceptInviteAsync(code)).EnsureSuccessStatusCode();

        return new Pair(groupId, owner, ownerClient, guest, guestSubject, guestClient);
    }

    /// The owner paid for both, so the guest is the debtor and the owner the creditor.
    private async Task<Pair> PairWhereGuestOwesAsync(decimal owed)
    {
        var pair = await PairAsync();
        await _factory.DrainProcessedAsync();

        (await pair.OwnerClient.CreateExpenseAsync(pair.GroupId,
            ExpenseBody(paidBy: pair.Owner.Id, pair.Owner.Id, pair.Guest.Id, share: owed))).EnsureSuccessStatusCode();
        await _factory.WaitForProcessedAsync();

        return pair;
    }

    private static object ExpenseBody(int paidBy, int first, int? second = null, decimal share = 5m)
    {
        var participants = second is null ? new[] { first } : new[] { first, second.Value };

        return new
        {
            paidBy,
            amount = share * participants.Length,
            description = "Dinner",
            splitMode = "equal",
            splits = participants.Select(userId => new { userId, amount = share }).ToArray()
        };
    }

    private static IEnumerable<JsonElement> Members(JsonElement group) =>
        group.GetProperty("members").EnumerateArray();

    private static JsonElement MemberOf(JsonElement group, int userId) =>
        Members(group).Single(m => m.GetProperty("userId").GetInt32() == userId);

    private Task<bool> GroupExistsAsync(int groupId) =>
        _factory.UseDbAsync(db => db.Group.AnyAsync(g => g.Id == groupId));

    private async Task<string> UploadAsync(ApiClient client)
    {
        var response = await client.CreateAvatarUploadAsync();
        response.EnsureSuccessStatusCode();

        var key = (await response.Content.ReadFromJsonAsync<JsonElement>(Json)).GetProperty("key").GetString()!;
        _storage.PutObject(key);

        return key;
    }

    private static async Task<ProfileSnapshot> ReadProfileAsync(Task<HttpResponseMessage> request)
    {
        var response = await request;
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);

        return new ProfileSnapshot(
            body.GetProperty("name").GetString()!,
            body.GetProperty("email").GetString()!,
            body.GetProperty("avatarUrl").GetString()!);
    }

    private sealed record ProfileSnapshot(string Name, string Email, string AvatarUrl);
}

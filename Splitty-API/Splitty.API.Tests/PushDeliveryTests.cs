using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Splitty.Service;

namespace Splitty.API.Tests;

/// <summary>
/// From a notice to the device: only signed-in devices of a user who wants the notice get it,
/// in the language the device registered, and a device Apple no longer knows is forgotten.
/// </summary>
[Collection(nameof(ApiCollection))]
public sealed class PushDeliveryTests(ApiFactory factory)
{
    private static string NewToken() => Convert.ToHexStringLower(Guid.NewGuid().ToByteArray()) +
                                        Convert.ToHexStringLower(Guid.NewGuid().ToByteArray());

    /// Runs the notice through the dispatcher directly, so the test needs no worker to wait for.
    private async Task DispatchAsync(Notice notice)
    {
        using var scope = factory.Services.CreateScope();
        await scope.ServiceProvider.GetRequiredService<PushDispatcher>().DispatchAsync(notice);
    }

    private static Notice Reminder(GroupFixture group) =>
        new(group.GuestId, NoticeMessage.PaymentReminder, group.Id, group.OwnerId) { Amount = 12.5m };

    [Fact]
    public async Task A_registered_device_gets_the_notice_in_the_language_it_registered()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var token = NewToken();
        Assert.Equal(HttpStatusCode.NoContent, (await group.Guest.RegisterPushDeviceAsync(token, "pt-BR")).StatusCode);

        await DispatchAsync(Reminder(group));

        var push = Assert.Single(factory.PushSender.SentTo(token));
        Assert.Equal("Trip", push.Title);
        Assert.Equal("Owner pediu o pagamento de $12.50", push.Body);
        Assert.Equal(group.Id, push.GroupId);
    }

    [Fact]
    public async Task A_kind_switched_off_or_the_main_switch_off_sends_nothing()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var token = NewToken();
        await group.Guest.RegisterPushDeviceAsync(token);

        (await group.Guest.UpdateNotificationSettingsAsync(true, "payment_reminder")).EnsureSuccessStatusCode();
        await DispatchAsync(Reminder(group));
        await DispatchAsync(new Notice(group.GuestId, NoticeMessage.PaymentReceived, group.Id, group.OwnerId) { Amount = 1m });

        (await group.Guest.UpdateNotificationSettingsAsync(false)).EnsureSuccessStatusCode();
        await DispatchAsync(new Notice(group.GuestId, NoticeMessage.PaymentReceived, group.Id, group.OwnerId) { Amount = 2m });

        var push = Assert.Single(factory.PushSender.SentTo(token));
        Assert.Equal("Owner paid you $1.00", push.Body);
    }

    [Fact]
    public async Task Settings_start_all_on_and_keep_the_muted_kinds_while_switched_off()
    {
        var user = await ApiClient.Create(factory).SignInAsync();
        var client = ApiClient.Create(factory, user.Token);

        var initial = await client.ReadJsonAsync(await client.GetNotificationSettingsAsync());
        Assert.True(initial.GetProperty("enabled").GetBoolean());
        Assert.Equal(0, initial.GetProperty("muted").GetArrayLength());

        await client.UpdateNotificationSettingsAsync(false, "expense_changed", "invite_accepted");
        var saved = await client.ReadJsonAsync(await client.GetNotificationSettingsAsync());

        Assert.False(saved.GetProperty("enabled").GetBoolean());
        Assert.Equal(["expense_changed", "invite_accepted"],
            saved.GetProperty("muted").EnumerateArray().Select(k => k.GetString()));
    }

    [Fact]
    public async Task An_unknown_kind_or_language_is_refused()
    {
        var user = await ApiClient.Create(factory).SignInAsync();
        var client = ApiClient.Create(factory, user.Token);

        await ErrorResponseAssertions.AssertErrorAsync(
            await client.RegisterPushDeviceAsync(NewToken(), "de"), HttpStatusCode.BadRequest);
        Assert.Equal(HttpStatusCode.BadRequest,
            (await client.UpdateNotificationSettingsAsync(true, "everything")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await client.RegisterPushDeviceAsync("not-hex")).StatusCode);
    }

    [Fact]
    public async Task Signing_out_stops_pushes_to_that_device_and_leaves_the_other_signed_in()
    {
        var email = $"{Guid.NewGuid():N}@splitty.test";
        var subject = Guid.NewGuid().ToString("N");
        var onPhone = await ApiClient.Create(factory).SignInAsync(email, subject: subject);
        var onTablet = await ApiClient.Create(factory).SignInAsync(email, subject: subject);
        var phone = NewToken();
        var tablet = NewToken();
        var groupId = await ApiClient.Create(factory, onPhone.Token).CreateGroupAsync();
        await ApiClient.Create(factory, onPhone.Token).RegisterPushDeviceAsync(phone);
        await ApiClient.Create(factory, onTablet.Token).RegisterPushDeviceAsync(tablet);

        (await ApiClient.Create(factory).LogoutAsync(onPhone.RefreshToken)).EnsureSuccessStatusCode();
        await DispatchAsync(new Notice(onPhone.Id, NoticeMessage.PaymentReceived, groupId, onPhone.Id) { Amount = 1m });

        Assert.Empty(factory.PushSender.SentTo(phone));
        Assert.Single(factory.PushSender.SentTo(tablet));
        Assert.False(await factory.UseDbAsync(db => db.PushDevice.AnyAsync(d => d.Token == phone)));
    }

    [Fact]
    public async Task A_device_moves_to_whoever_registers_it_last()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var token = NewToken();
        await group.Guest.RegisterPushDeviceAsync(token);
        await group.Owner.RegisterPushDeviceAsync(token);

        await DispatchAsync(Reminder(group));

        Assert.Empty(factory.PushSender.SentTo(token));
        Assert.Equal(group.OwnerId, await factory.UseDbAsync(db => db.PushDevice.Where(d => d.Token == token)
            .Select(d => d.UserId).SingleAsync()));
    }

    [Fact]
    public async Task A_device_apple_no_longer_knows_is_forgotten()
    {
        var group = await GroupFixture.CreateAsync(factory);
        var token = NewToken();
        await group.Guest.RegisterPushDeviceAsync(token);
        factory.PushSender.Unregistered[token] = true;

        await DispatchAsync(Reminder(group));

        Assert.False(await factory.UseDbAsync(db => db.PushDevice.AnyAsync(d => d.Token == token)));
    }

    [Fact]
    public async Task Deleting_the_account_forgets_its_devices()
    {
        var user = await ApiClient.Create(factory).SignInAsync();
        var client = ApiClient.Create(factory, user.Token);
        await client.RegisterPushDeviceAsync(NewToken());

        (await client.DeleteAccountAsync()).EnsureSuccessStatusCode();

        Assert.False(await factory.UseDbAsync(db => db.PushDevice.AnyAsync(d => d.UserId == user.Id)));
    }

    [Fact]
    public void The_apns_payload_carries_the_alert_the_thread_and_what_to_open()
    {
        var payload = ApnsPushSender.Payload(new Splitty.Service.Interfaces.Push("Trip", "Hi", 7, 42));

        var json = JsonDocument.Parse(payload.ToJsonString()).RootElement;
        Assert.Equal("Trip", json.GetProperty("aps").GetProperty("alert").GetProperty("title").GetString());
        Assert.Equal("Hi", json.GetProperty("aps").GetProperty("alert").GetProperty("body").GetString());
        Assert.Equal("group-7", json.GetProperty("aps").GetProperty("thread-id").GetString());
        Assert.Equal(7, json.GetProperty("groupId").GetInt32());
        Assert.Equal(42, json.GetProperty("expenseId").GetInt32());
    }
}

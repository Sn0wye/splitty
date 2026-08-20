using Splitty.Domain.Entities;
using Splitty.Service.Interfaces;

namespace Splitty.API.Tests;

/// <summary>
/// Passes every call through, so a test substitute only has to say how the one method
/// it cares about differs.
/// </summary>
public abstract class BalanceServiceDecorator(IBalanceService inner) : IBalanceService
{
    public virtual Task<List<Balance>> CalculateGroupBalances(int groupId) =>
        inner.CalculateGroupBalances(groupId);

    public Task<List<Balance>> GetGroupUserBalance(int groupId, int userId) =>
        inner.GetGroupUserBalance(groupId, userId);

    public Task SettleUp(int groupId, int userId, int peerId, decimal amount) =>
        inner.SettleUp(groupId, userId, peerId, amount);
}

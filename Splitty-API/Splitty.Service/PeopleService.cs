using Splitty.DTO.Response;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public class PeopleService(
    IGroupMembershipRepository groupMembershipRepository,
    IBalanceRepository balanceRepository
) : IPeopleService
{
    public async Task<PeopleResponse> GetPeopleAsync(int userId)
    {
        var peerMemberships = await groupMembershipRepository.GetPeerMembershipsAsync(userId);
        var balances = await balanceRepository.GetUserBalancesAsync(userId);

        // Keyed by the live memberships below, so a stale row from a group either side has
        // since left is never read.
        var amounts = balances.ToDictionary(b => (b.PeerId, b.GroupId), b => b.Amount);

        var peers = peerMemberships
            .GroupBy(m => m.UserId)
            .OrderBy(byPeer => byPeer.Key)
            .Select(byPeer =>
            {
                var groups = byPeer
                    .OrderBy(m => m.GroupId)
                    .Select(m => new PeerGroupResponse
                    {
                        GroupId = m.GroupId,
                        GroupName = m.Group.Name,
                        Amount = amounts.GetValueOrDefault((byPeer.Key, m.GroupId))
                    })
                    .ToList();

                var user = byPeer.First().User;

                return new PeerResponse
                {
                    UserId = byPeer.Key,
                    Name = user.Name,
                    AvatarUrl = user.AvatarUrl,
                    NetAmount = groups.Sum(g => g.Amount),
                    Groups = groups
                };
            })
            .ToList();

        return new PeopleResponse
        {
            Peers = peers,
            BalancesPending = peerMemberships.Any(m => m.Group.BalancesPending)
        };
    }
}

using Splitty.DTO.Response;
using Splitty.Repository.Interfaces;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public class PeopleService(
    IGroupMembershipRepository groupMembershipRepository,
    IBalanceRepository balanceRepository,
    IAvatarResolver avatarResolver
) : IPeopleService
{
    public async Task<PeopleResponse> GetPeopleAsync(int userId)
    {
        var peerMemberships = await groupMembershipRepository.GetPeerMembershipsAsync(userId);
        var balances = await balanceRepository.GetUserSimplifiedDebtsAsync(userId);

        // Keyed by the live memberships below, so a stale row from a group either side has
        // since left is never read.
        var amounts = balances.ToDictionary(
            d => (d.FromUserId == userId ? d.ToUserId : d.FromUserId, d.GroupId),
            d => d.FromUserId == userId ? -d.Amount : d.Amount);

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
                    AvatarUrl = avatarResolver.Resolve(user),
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

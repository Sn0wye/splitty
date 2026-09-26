using Splitty.DTO.Response;

namespace Splitty.Service.Interfaces;

public interface IGroupStatsService
{
    Task<GroupStatsResponse> GetStatsAsync(int groupId, int userId, StatsRange range);
}

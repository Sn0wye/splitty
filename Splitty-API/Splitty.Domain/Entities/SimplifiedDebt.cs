using System.ComponentModel.DataAnnotations.Schema;

namespace Splitty.Domain.Entities;

[Table("SimplifiedDebt")]
public class SimplifiedDebt
{
    public int GroupId { get; set; }
    public int FromUserId { get; set; }
    public int ToUserId { get; set; }
    public decimal Amount { get; set; }
    public User FromUser { get; set; } = null!;
    public User ToUser { get; set; } = null!;
    public Group Group { get; set; } = null!;
}

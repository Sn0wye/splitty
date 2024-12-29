using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json.Serialization;

namespace Splitty.Domain.Entities;

[Table("Balance")]
public class Balance
{
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public int Id { get; init; }
    public int UserId { get; set; }
    public int GroupId { get; set; }
    public int PeerId { get; set; }
    public Decimal Amount { get; set; }
    
    public virtual User User { get; init; }
    public virtual User Peer { get; init; }
    [JsonIgnore]
    public virtual Group Group { get; init; }
}
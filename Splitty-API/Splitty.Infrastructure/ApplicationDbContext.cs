using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.Configuration;

namespace Splitty.Infrastructure;

public class ApplicationDbContext : DbContext
{
    private readonly string _connectionString;

    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options, IConfiguration configuration)
        : base(options)
    {
        _connectionString = configuration.GetConnectionString("DefaultConnection");
    }

    protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
    {
        optionsBuilder.UseNpgsql(_connectionString)
            .ConfigureWarnings(w => w.Ignore(RelationalEventId.PendingModelChangesWarning));
    }

    public DbSet<Domain.Entities.User> User { get; set; }
    public DbSet<Domain.Entities.Group> Group { get; set; }
    public DbSet<Domain.Entities.GroupMembership> GroupMembership { get; set; }
    public DbSet<Domain.Entities.Expense> Expense { get; set; }
    public DbSet<Domain.Entities.ExpenseSplit> ExpenseSplit { get; set; }
    public DbSet<Domain.Entities.Balance> Balance { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Domain.Entities.User>(entity =>
        {
            entity.HasKey(u => u.Id);
            entity.Property(u => u.Name).IsRequired().HasMaxLength(255);
            entity.Property(u => u.Email).IsRequired().HasMaxLength(255);
            entity.Property(u => u.Password).IsRequired();
            entity.Property(u => u.CreatedAt).IsRequired();
            entity.Property(u => u.UpdatedAt).IsRequired();
        });

        modelBuilder.Entity<Domain.Entities.Group>(entity =>
        {
            entity.HasKey(g => g.Id);
            entity.Property(g => g.Name).IsRequired().HasMaxLength(100);
            entity.Property(g => g.Description).HasMaxLength(500);
            entity.Property(g => g.CreatedAt).IsRequired();
            entity.Property(g => g.CreatedBy).IsRequired();

            entity.HasOne(g => g.CreatedByUser)
                .WithMany()
                .HasForeignKey(g => g.CreatedBy)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasMany(g => g.Members)
                .WithOne(gm => gm.Group)
                .HasForeignKey(gm => gm.GroupId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasMany(g => g.Balances)
                .WithOne(b => b.Group)
                .HasForeignKey(b => b.GroupId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<Domain.Entities.GroupMembership>(entity =>
        {
            entity.HasKey(gm => gm.Id);
            entity.Property(gm => gm.JoinedAt).IsRequired();
            
            entity.HasIndex(gm => gm.GroupId);
            entity.HasIndex(gm => gm.UserId);

            entity.HasOne(gm => gm.User)
                .WithMany()
                .HasForeignKey(gm => gm.UserId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(gm => gm.Group)
                .WithMany(g => g.Members)
                .HasForeignKey(gm => gm.GroupId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<Domain.Entities.Expense>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Amount).IsRequired().HasColumnType("decimal(18,2)");
            entity.Property(e => e.Description).HasMaxLength(500);
            entity.Property(e => e.Type).IsRequired().HasDefaultValue(Domain.Entities.ExpenseType.Expense);
            entity.Property(e => e.CreatedAt).IsRequired();
            entity.Property(e => e.UpdatedAt).IsRequired();

            entity.HasOne(e => e.PaidByUser)
                .WithMany()
                .HasForeignKey(e => e.PaidBy)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasOne(e => e.Group)
                .WithMany()
                .HasForeignKey(e => e.GroupId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<Domain.Entities.ExpenseSplit>(entity =>
        {
            entity.HasKey(es => es.Id);
            entity.Property(es => es.Amount).IsRequired().HasColumnType("decimal(18,2)");

            entity.HasOne(es => es.Expense)
                .WithMany(e => e.Splits)
                .HasForeignKey(es => es.ExpenseId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(es => es.User)
                .WithMany()
                .HasForeignKey(es => es.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<Domain.Entities.Balance>(entity =>
        {
            entity.HasKey(b => b.Id);
            entity.Property(b => b.Amount).IsRequired().HasColumnType("decimal(18,2)");

            entity.HasOne(b => b.User)
                .WithMany()
                .HasForeignKey(b => b.UserId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(b => b.Peer)
                .WithMany()
                .HasForeignKey(b => b.PeerId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(b => b.Group)
                .WithMany(g => g.Balances)
                .HasForeignKey(b => b.GroupId)
                .OnDelete(DeleteBehavior.Cascade);
        });
    }
}
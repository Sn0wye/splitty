FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS base
# The health check below, and Coolify's, run curl inside the container; the aspnet image ships
# neither curl nor wget. Installed before USER drops root.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
USER $APP_UID
WORKDIR /app
EXPOSE 8080
EXPOSE 8081

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src
COPY ["Splitty.sln", "."]
COPY ["Splitty.API/Splitty.API.csproj", "Splitty.API/"]
COPY ["Splitty.Domain/Splitty.Domain.csproj", "Splitty.Domain/"]
COPY ["Splitty.Infrastructure/Splitty.Infrastructure.csproj", "Splitty.Infrastructure/"]
COPY ["Splitty.Repository/Splitty.Repository.csproj", "Splitty.Repository/"]
COPY ["Splitty.Service/Splitty.Service.csproj", "Splitty.Service/"]
COPY ["Splitty.DTO/Splitty.DTO.csproj", "Splitty.DTO/"]
COPY ["Splitty.Background/Splitty.Background.csproj", "Splitty.Background/"]
COPY ["Splitty.Seeder/Splitty.Seeder.csproj", "Splitty.Seeder/"]
RUN dotnet restore "Splitty.API/Splitty.API.csproj"
COPY . .
WORKDIR "/src/Splitty.API"
# Publish compiles the project itself; a separate build step compiled it twice.
RUN dotnet publish "Splitty.API.csproj" -c $BUILD_CONFIGURATION -o /app/publish --no-restore /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=build /app/publish .
# Liveness only: a database outage should not restart a container that cannot fix it.
# The start period covers migrations, which run before Kestrel listens.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -fsS http://localhost:8080/healthz/livez || exit 1
ENTRYPOINT ["dotnet", "Splitty.API.dll"]

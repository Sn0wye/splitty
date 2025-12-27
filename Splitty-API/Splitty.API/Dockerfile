FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS base
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
RUN dotnet build "Splitty.API.csproj" -c $BUILD_CONFIGURATION -o /app/build

FROM build AS publish
ARG BUILD_CONFIGURATION=Release
RUN dotnet publish "Splitty.API.csproj" -c $BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "Splitty.API.dll"]

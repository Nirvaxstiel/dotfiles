# syntax=docker/dockerfile:1
FROM nousresearch/hermes-agent:latest

USER root
ENV DOTNET_ROOT=/usr/share/dotnet

# Trust Zscaler root CA for apt, curl, dotnet, nuget, etc.
# Uncomment if required
# COPY zscaler-root-ca.crt /usr/local/share/ca-certificates/zscaler-root-ca.crt

RUN --mount=type=cache,target=/var/cache/apt,sharing=local \
    --mount=type=cache,target=/var/lib/apt,sharing=local \
    set -eux; \
    update-ca-certificates; \
    rm -rf /etc/apt/apt.conf.d/docker-clean; \
    apt-get update; \
    apt-get install -y --no-install-recommendations \
        curl \
        ca-certificates; \
    # hermes-agent's image runs on a debian image. so we will match this
    curl -fsSL -o /tmp/ms.deb https://packages.microsoft.com/config/debian/13/packages-microsoft-prod.deb; \
    dpkg -i /tmp/ms.deb; \
    rm -f /tmp/ms.deb; \
    apt-get update; \
    apt-get install -y --no-install-recommendations \
        dotnet-sdk-10.0 \
        # dotnet-sdk-8.0 \
        aspnetcore-runtime-10.0 \
        aspnetcore-runtime-8.0

# Shit happens. Need writable dirs.
RUN install -d -o hermes -g hermes /home/user/projects /opt/hermes \
    && if [ -d /home/user/projects ]; then chown -R hermes:hermes /home/user/projects; fi \
    && if [ -d /opt/hermes/ui-tui ]; then chown -R hermes:hermes /opt/hermes/ui-tui; fi \
    && if [ -d /opt/hermes/.venv ]; then chown -R hermes:hermes /opt/hermes/.venv; fi

USER hermes
ENV PATH=/home/hermes/.dotnet/topols:$PATH

RUN --mount=type=cache,target=/home/hermes/.nuget,uid=1000,gid=1000,sharing=locked \
    dotnet tool install --global roslyn-language-server --prerelease
    # --global csharp-ls

RUN --mount=type=cache,target=/home/hermes/.cache/uv,uid=1000,gid=1000,sharing=locked \
    uv tool install graphify && graphify install --platform hermes
    # uv pip install \
    #     jcodemunch-mcp
    #     hermes-agent[web]
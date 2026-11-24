# AiMMO dedicated server for Railway.
# Runs the Godot project from source in headless mode (no export templates needed).
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.3-stable
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
 && curl -fsSL -o /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" \
 && unzip -q /tmp/godot.zip -d /opt/godot \
 && ln -s "/opt/godot/Godot_v${GODOT_VERSION}_linux.x86_64" /usr/local/bin/godot \
 && rm /tmp/godot.zip \
 && apt-get purge -y curl unzip && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY game/ /app/game/
COPY tests/ /app/tests/
COPY db/ /app/db/
COPY CHANGELOG.md /app/CHANGELOG.md
COPY docker/entrypoint.sh docker/probe.sh /app/

# Build Godot's script class cache and import resources at build time, not on every boot.
RUN godot --headless --path /app/game --import >/dev/null 2>&1 || true \
 && test -f /app/game/.godot/global_script_class_cache.cfg

# MAX_PLAYERS: the always-on world is for 2 to 8 friends (owner direction 8). A ninth login is
# turned away politely ("The world is full (8 / 8)") and nobody inside is kicked. The bot test's
# player-cap phase plays exactly this cap (tests/bot_test/run_bot_test.py, CAP_PLAYERS).
ENV AIMMO_TRANSPORT=websocket \
    AIMMO_PORT=7777 \
    AIMMO_MIGRATIONS_DIR=/app/db/migrations \
    AIMMO_DATA_DIR=/app/data \
    MAX_PLAYERS=8

EXPOSE 7777
# The entrypoint also runs a watchdog that restarts a frozen server (see docker/entrypoint.sh).
CMD ["/app/entrypoint.sh"]

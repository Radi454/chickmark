# Cloud Run image for the Pip Realtime sideband/control service.
#
# One npm dependency: `ws`, used by src/sideband.ts to attach to the live
# OpenAI Realtime call. Deno's built-in WebSocket cannot set the
# `Authorization` header that attach requires (proven against the live
# endpoint — see the comment above connectSideband in src/sideband.ts), and
# Deno's WebSocketStream negotiates h2, which OpenAI 400s. `ws` over
# http/1.1 with a header is the only transport that has actually passed auth,
# so it ships in the runtime image, not just the test graph.

FROM denoland/deno:2.9.5

WORKDIR /app

# Dependency manifest first so the cache layer survives source edits. The
# lockfile ships too: without it a rebuild can resolve different dependency
# versions than the ones this service was tested against.
COPY deno.json deno.lock ./
COPY main.ts ./
COPY src/ ./src/

# Compile and cache the dependency graph at build time. A type error fails the
# BUILD rather than the first request.
RUN deno check main.ts

# Cloud Run injects PORT; the server reads it and defaults to 8080.
ENV PORT=8080
EXPOSE 8080

USER deno

# --allow-net: Supabase REST + JWKS, the OpenAI Realtime socket, Google's OIDC
# certs. --allow-env: configuration. Nothing else is granted; there is no
# filesystem or subprocess access in this service.
CMD ["run", "--allow-net", "--allow-env", "main.ts"]

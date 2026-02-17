# syntax=docker/dockerfile:1

FROM rust:1.76-bookworm AS builder
WORKDIR /workspace

# Copy only keeper sources for a smaller build context.
COPY keeper-rs/Cargo.toml keeper-rs/Cargo.toml
COPY keeper-rs/src keeper-rs/src

RUN cargo build --manifest-path keeper-rs/Cargo.toml --release

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /workspace/keeper-rs/target/release/opensub-keeper /usr/local/bin/opensub-keeper

WORKDIR /work
ENTRYPOINT ["opensub-keeper"]

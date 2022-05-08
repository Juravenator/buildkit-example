# syntax=docker/dockerfile:1.4

## Dockerfile that enables you to run various targets for building & testing
## Use it by running `docker build . --target <desired_target>`
## Note that if a stage isn't referenced (by e.g. `COPY --from=<stage>`), it will not be built

##
## Building
##

## Name our base image for later re-use. And use it right away to populate our caches.
FROM golang:1.17-bullseye AS base
# Setting our workdir as early as possible, used by subsequent stages
WORKDIR /src
#   read-only mount of our context, containing our source tree
RUN --mount=target=. \
#   cache mount, in which we'll fetch our go packages
    --mount=type=cache,target=/go/pkg/mod \
    go mod download

## Builder of the binary
FROM base as builder
RUN --mount=target=. \
    --mount=type=cache,target=/go/pkg/mod \
#   extra cache mount, build caches for re-use during tests & future re-runs
    --mount=type=cache,target=/root/.cache/go-build \
    make build.local

## A runner image will need instantclient files
FROM debian:bullseye as instantclient
RUN apt-get update && \
    apt-get install -y ca-certificates && \
    apt-get install -y --no-install-recommends curl unzip && \
    curl -LO https://download.oracle.com/otn_software/linux/instantclient/215000/instantclient-basic-linux.x64-21.5.0.0.0dbru.zip && \
    curl -LO https://download.oracle.com/otn_software/linux/instantclient/215000/instantclient-sqlplus-linux.x64-21.5.0.0.0dbru.zip && \
    mkdir -p /opt/oracle && \
    unzip instantclient-basic-linux.x64-21.5.0.0.0dbru.zip -d /opt/oracle && \
    unzip instantclient-sqlplus-linux.x64-21.5.0.0.0dbru.zip -d /opt/oracle

##
## Testing
##

## Linting image where we will extract linting binaries from
FROM golangci/golangci-lint:v1.43-alpine AS lint-base
## Perform our code linting
FROM base AS lint
RUN --mount=target=. \
    --mount=from=lint-base,src=/usr/bin/golangci-lint,target=/usr/bin/golangci-lint \
    --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/root/.cache/golangci-lint \
    golangci-lint run --timeout 10m0s ./...

## Unit test time
FROM base as test-golang
RUN --mount=target=. \
    --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    make test.golang.local

## Coverage target for extracting a coverage report of the unit tests earlier
FROM scratch AS coverage
COPY --from=test-golang /tmp/cover.out /cover.out

## BATS testing framework setup
FROM alpine:3 as bats-base
RUN apk add make bash git parallel
RUN git clone https://github.com/bats-core/bats-core.git /tmp/bats-core && \
    cd /tmp/bats-core && ./install.sh /usr/local
RUN git clone https://github.com/bats-core/bats-support.git /usr/lib/bats/bats-support
RUN git clone https://github.com/bats-core/bats-assert.git /usr/lib/bats/bats-assert
RUN git clone https://github.com/jasonkarns/bats-mock /usr/lib/bats/bats-mock
WORKDIR /src
ENV BATS_LIB_PATH=/usr/lib/bats
## BATS unit tests
FROM bats-base as test-bats
COPY --link --from=builder /tmp/query /
ARG TEST_SLOW_PATH
RUN --mount=target=. \
    TEST_SLOW_PATH=${TEST_SLOW_PATH} QUERY_PATH=/query make test.bats.local

##
## Packaging
##

## The bin target for extracting a runnable binary from the build earlier
FROM scratch as bin
COPY --from=builder /tmp /

## Packaging a runnable image
## This target goes last in the list, since it is the end-product expected from running a bare 'docker build'
FROM debian:bullseye as containerimage

RUN mkdir -p /opt/oracle && \
    apt-get update && \
    apt-get install -y --no-install-recommends libaio1 make && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --link src/assess.sh /
COPY --link --from=builder /tmp/query /
COPY --link --from=instantclient /opt/oracle /opt/oracle

ENV LD_LIBRARY_PATH=/opt/oracle/instantclient_21_5:$LD_LIBRARY_PATH \
    PATH=/opt/oracle/instantclient_21_5:$PATH

WORKDIR /
CMD  ["/query"]

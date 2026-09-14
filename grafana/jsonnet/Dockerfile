FROM golang:1.25-alpine

RUN apk add --no-cache \
    git \
    build-base

RUN go install github.com/google/go-jsonnet/cmd/jsonnet@v0.22.0 \
    && go install github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb@latest

WORKDIR /work

ENTRYPOINT ["/bin/sh"]
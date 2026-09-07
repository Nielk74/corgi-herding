FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG VERSION=development
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -X main.version=${VERSION}" -o /out/corgi-server ./cmd/server

FROM alpine:3.22
RUN apk add --no-cache ca-certificates && addgroup -S corgi && adduser -S -G corgi corgi && mkdir /data && chown corgi:corgi /data
COPY --from=build /out/corgi-server /usr/local/bin/corgi-server
USER corgi
ENV CORGI_ADDR=:8790 CORGI_STATE_DIR=/data
EXPOSE 8790
VOLUME /data
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 CMD wget -q -O /dev/null http://127.0.0.1:8790/healthz || exit 1
ENTRYPOINT ["/usr/local/bin/corgi-server"]

# KamuBul arka ucu: API sunucusu (/app/server) ve çekim işi (/app/job) aynı
# imajdadır. Bağlam depo kökü olmalıdır (kamubul_core yol bağımlılığı için):
#   docker build -f backend/Dockerfile -t kamubul-backend .
FROM dart:3.13 AS build
WORKDIR /src
COPY packages/kamubul_core packages/kamubul_core
COPY backend backend
WORKDIR /src/backend
RUN dart pub get && \
    dart compile exe bin/server.dart -o /out/server && \
    dart compile exe bin/job.dart -o /out/job

# /runtime/ AOT ikilisi için gereken en küçük çalışma ortamıdır (libc + CA).
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /out/server /app/server
COPY --from=build /out/job /app/job
# Sunucu saat dilimi UTC olmalıdır: tarihler Türkiye duvar saati olarak
# ayrı işlenir (wallClock), yerel saat dilimi karışmamalıdır.
ENV TZ=UTC PORT=8080
EXPOSE 8080
# Varsayılan: API. Çekim işi için komutu /app/job olarak geçin.
CMD ["/app/server"]

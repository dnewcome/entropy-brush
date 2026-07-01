# --- build the Flutter web bundle ---
FROM ghcr.io/cirruslabs/flutter:3.41.6 AS build
WORKDIR /app

# Cache deps first.
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Build.
COPY . .
RUN flutter build web --release

# --- serve the static bundle with nginx ---
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]

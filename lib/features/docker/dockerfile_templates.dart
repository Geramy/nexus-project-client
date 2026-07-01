// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:nexus_projects_client/infrastructure/workspace/workspace.dart';

/// A prefilled container recipe for a project: a starter [dockerfile] tuned to
/// the detected [kind], the container port the image exposes, and a sensible
/// default host port. The user edits any of these before launching, and the
/// Dockerfile is written into the project so it can be edited later too.
class DockerLaunchTemplate {
  final String kind;
  final String dockerfile;
  final int containerPort;
  final int hostPort;
  const DockerLaunchTemplate({
    required this.kind,
    required this.dockerfile,
    required this.containerPort,
    required this.hostPort,
  });
}

/// Detect the project's stack from the files in its [ws], so we can prefill a
/// stack-appropriate Dockerfile. Best-effort; defaults to `generic`.
Future<String> detectDockerStackKind(Workspace ws) async {
  Future<bool> has(String p) => ws.exists(p.startsWith('/') ? p : '/$p');

  if (await has('pubspec.yaml')) {
    // Flutter vs plain Dart: a Flutter app depends on the flutter SDK.
    try {
      final pubspec = await ws.readString('/pubspec.yaml');
      if (pubspec.contains('flutter:') || pubspec.contains('sdk: flutter')) {
        return 'flutter';
      }
    } catch (_) {}
    return 'dart';
  }
  if (await has('package.json')) return 'node';
  if (await has('requirements.txt') ||
      await has('pyproject.toml') ||
      await has('Pipfile')) {
    return 'python';
  }
  if (await has('go.mod')) return 'go';
  if (await has('Cargo.toml')) return 'rust';

  // .NET projects: scan for a project/solution file.
  try {
    final files = (await ws.walk())
        .where((f) => !f.isDirectory)
        .map((f) => f.path.toLowerCase());
    if (files.any((f) => f.endsWith('.csproj') || f.endsWith('.sln'))) {
      return 'dotnet';
    }
  } catch (_) {}

  return 'generic';
}

/// Build a prefilled [DockerLaunchTemplate] for [kind]. These are STARTER
/// recipes — correct for a typical project of that stack and meant to be edited.
DockerLaunchTemplate dockerLaunchTemplate(String kind) {
  switch (kind) {
    case 'flutter':
      // A Flutter desktop/mobile binary can't run in a Linux container, but the
      // web build can — compile it and serve the static site with nginx.
      return const DockerLaunchTemplate(
        kind: 'flutter',
        containerPort: 80,
        hostPort: 8080,
        dockerfile: '''
# --- Build the Flutter web app ---
FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app
COPY . .
# Add the web platform if the project wasn't scaffolded for it (safe: only
# generates the missing web/ shell + config, never touches lib/ source).
RUN flutter create . --platforms web
RUN flutter pub get
RUN flutter build web --release

# --- Serve the static build with nginx ---
FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
''',
      );
    case 'dart':
      return const DockerLaunchTemplate(
        kind: 'dart',
        containerPort: 8080,
        hostPort: 8080,
        dockerfile: '''
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart compile exe bin/main.dart -o bin/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/bin/server /app/bin/server
EXPOSE 8080
CMD ["/app/bin/server"]
''',
      );
    case 'node':
      return const DockerLaunchTemplate(
        kind: 'node',
        containerPort: 3000,
        hostPort: 3000,
        dockerfile: '''
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev
COPY . .
EXPOSE 3000
CMD ["npm", "start"]
''',
      );
    case 'python':
      return const DockerLaunchTemplate(
        kind: 'python',
        containerPort: 8000,
        hostPort: 8000,
        dockerfile: '''
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8000
# Edit this to your app's entrypoint (module:app for ASGI/WSGI, or a script).
CMD ["python", "main.py"]
''',
      );
    case 'go':
      return const DockerLaunchTemplate(
        kind: 'go',
        containerPort: 8080,
        hostPort: 8080,
        dockerfile: '''
FROM golang:1.22-alpine AS build
WORKDIR /app
COPY go.* ./
RUN go mod download
COPY . .
RUN go build -o /app/server ./...

FROM alpine:latest
COPY --from=build /app/server /server
EXPOSE 8080
CMD ["/server"]
''',
      );
    case 'rust':
      return const DockerLaunchTemplate(
        kind: 'rust',
        containerPort: 8080,
        hostPort: 8080,
        dockerfile: '''
FROM rust:latest AS build
WORKDIR /app
COPY . .
RUN cargo build --release

FROM debian:bookworm-slim
COPY --from=build /app/target/release/app /usr/local/bin/app
EXPOSE 8080
CMD ["app"]
''',
      );
    case 'dotnet':
      return const DockerLaunchTemplate(
        kind: 'dotnet',
        containerPort: 8080,
        hostPort: 8080,
        dockerfile: '''
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY . .
RUN dotnet restore
RUN dotnet publish -c Release -o /app

FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY --from=build /app ./
EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080
# Edit this to your published entry assembly.
ENTRYPOINT ["dotnet", "App.dll"]
''',
      );
    default:
      return const DockerLaunchTemplate(
        kind: 'generic',
        containerPort: 8080,
        hostPort: 8080,
        dockerfile: '''
# Starter Dockerfile — edit for your project's stack.
FROM alpine:latest
WORKDIR /app
COPY . .
EXPOSE 8080
CMD ["sh", "-c", "echo 'Edit this Dockerfile to build and run your project' && sleep infinity"]
''',
      );
  }
}

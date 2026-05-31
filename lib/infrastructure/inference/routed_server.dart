// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// The Nexus Router — the metered subscription gateway — is surfaced as a
/// built-in inference server whenever the user is signed in. It is detected by
/// this sentinel [providerType] (no schema column needed) and its API key is the
/// account token the gateway mints on login.
library;

/// providerType sentinel that marks an InferenceServer row as the managed
/// Nexus Router subscription endpoint (vs. a user-added server).
const String kRoutedProviderType = 'routed';

/// Display name for the built-in Router server row.
const String kRouterServerName = 'Nexus Router (Subscription)';

/// True when a server row is the managed Nexus Router endpoint.
bool isRoutedProviderType(String? providerType) =>
    (providerType ?? '').toLowerCase() == kRoutedProviderType;

// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Response shape for `/v1/images/generations` and `/v1/images/edits`.

class ImageResponse {
  final List<GeneratedImage> images;
  const ImageResponse(this.images);
  factory ImageResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final list = (data is List
        ? data
              .whereType<Map<String, dynamic>>()
              .map(GeneratedImage.fromJson)
              .toList()
        : <GeneratedImage>[]);
    return ImageResponse(list);
  }
}

class GeneratedImage {
  final String? b64Json;
  final String? url;
  const GeneratedImage({this.b64Json, this.url});
  factory GeneratedImage.fromJson(Map<String, dynamic> json) => GeneratedImage(
    b64Json: json['b64_json'] as String?,
    url: json['url'] as String?,
  );
}

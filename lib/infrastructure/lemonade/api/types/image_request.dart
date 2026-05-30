// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Body for `POST /v1/images/generations`.

class ImageGenerationRequest {
  final String model;
  final String prompt;
  final int? width;
  final int? height;
  final int n;
  final String responseFormat; // 'b64_json' | 'url'
  final int? seed;

  const ImageGenerationRequest({required this.model, required this.prompt, this.width, this.height, this.n = 1, this.responseFormat = 'b64_json', this.seed});

  factory ImageGenerationRequest.bySize({required String model, required String prompt, String? size = '1024x1024', int n = 1, int? seed}) {
    int? w;
    int? h;
    if (size != null) {
      final parts = size.split('x');
      if (parts.length == 2) {
        w = int.tryParse(parts[0]);
        h = int.tryParse(parts[1]);
      }
    }
    return ImageGenerationRequest(model: model, prompt: prompt, width: w, height: h, n: n, responseFormat: 'url', seed: seed);
  }

  Map<String, dynamic> toWireJson() {
    final body = <String, dynamic>{'model': model, 'prompt': prompt};
    if (width != null) body['size'] = '${width}x$height';
    else body['size'] = '1024x1024';
    if (n > 1) body['n'] = n;
    body['response_format'] = responseFormat;
    return body..addAll(seed != null ? {'seed': seed} : const {});
  }

  Map<String, dynamic> toWireJsonLegacy() {
    final body = <String, dynamic>{'model': model, 'prompt': prompt};
    if (width != null && height != null) {
      body['size'] = '$width x $height';
    } else {
      body['n'] = n;
      body['response_format'] = responseFormat;
    }
    return body..addAll(seed != null ? {'seed': seed} : const {});
  }
}

// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import '../exceptions.dart';
import '../lemonade_client.dart';
import '../types/image_request.dart';
import '../types/image_response.dart';

class ImagesEndpoint {
  final LemonadeApiClient _client;
  const ImagesEndpoint(this._client);

  /// `POST /v1/images/generations`
  Future<ImageResponse> generate(ImageGenerationRequest request, {Duration? timeout}) async {
    final body = await _client.postJson(_client.apiUriFor('/images/generations'), request.toWireJson(), timeout: timeout ?? const Duration(minutes: 4));
    return ImageResponse.fromJson(body);
  }

  /// `POST /v1/images/edits` (multipart/form-data).
  Future<ImageResponse> edit(ImageEditRequest request, {Duration? timeout}) async {
    final fields = <String, String>{'model': request.model, 'prompt': request.prompt, 'response_format': request.responseFormat, 'n': '${request.n}'};
    if (request.size != null) fields['size'] = request.size!;

    final body = await _client.postMultipart(
      _client.apiUriFor('/images/edits'),
      fields: fields, files: [
        MultipartFile(field: 'image', filename: request.sourceFilename, bytes: request.sourceImageBytes, mimeType: request.sourceImageMime),
      ], timeout: timeout ?? const Duration(minutes: 4));

    return ImageResponse.fromJson(body);
  }
}

/// Body for `POST /v1/images/edits`.
class ImageEditRequest {
  final String model;
  final String prompt;
  final int n;
  final String responseFormat; // 'b64_json' | 'url'
  final String? size;
  final List<int> sourceImageBytes;
  final String sourceFilename;
  final String sourceImageMime;

  const ImageEditRequest({required this.model, required this.prompt, required this.sourceImageBytes, this.size = '1024x1024', this.n = 1, this.responseFormat = 'b64_json', this.sourceFilename = 'image.png', this.sourceImageMime = 'image/png'});
}

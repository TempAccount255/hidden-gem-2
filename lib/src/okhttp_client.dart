import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart';
import 'package:jni/jni.dart';

import 'jni/jni_bindings.dart';

class OkhttpClient extends BaseClient {
  bool _isClosed = false;
  final _kotlinBridge = KotlinBridge();

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    if (_isClosed) {
      throw ClientException(
          'HTTP request failed. Client is already closed.', request.url);
    }

    final client = OkHttpClient()
        .newBuilder()
        .followRedirects(request.followRedirects)
        .build();

    final builder = Request_Builder();

    builder.url1(request.url.toString().toJString());

    request.headers.forEach(
        (key, value) => builder.header(key.toJString(), value.toJString()));

    builder.method(request.method.toJString(),
        _initRequestBody(request.method, await request.finalize().toBytes()));

    final call = client.newCall(builder.build());

    final response = await _kotlinBridge.executeAsync(call);

    final statusCode = response.code();
    final reasonPhrase = response.message().toDartString(releaseOriginal: true);
    final responseHeaders = _responseHeaders(response.headers1());
    final isRedirect = response.isRedirect();

    Stream<List<int>> responseBodyStream() async* {
      const bufferSize = 4 * 1024;
      final bytesArray = JArray(jbyte.type, bufferSize);
      final bodyStream = response.body().source();

      while (true) {
        final bytesCount = bodyStream.read(bytesArray);
        if (bytesCount == -1) break;
        yield bytesArray.toUint8List(length: bytesCount);
      }

      client.release();
      builder.release();
      response.release();
      call.release();
    }

    return StreamedResponse(responseBodyStream(), statusCode,
        isRedirect: isRedirect,
        contentLength: _contentLength(responseHeaders),
        request: request,
        headers: responseHeaders,
        reasonPhrase: reasonPhrase);
  }

  int? _contentLength(Map<String, String> headers) {
    final contentLength = headers['content-length'];
    if (contentLength == null) return null;

    try {
      final parsedContentLength = int.parse(contentLength);
      if (parsedContentLength < 0) {
        throw ClientException(
            'Invalid content-length header [$contentLength].');
      }
      return parsedContentLength;
    } on FormatException {
      throw ClientException('Invalid content-length header [$contentLength].');
    }
  }

  Map<String, String> _responseHeaders(Headers responseHeaders) {
    final headers = <String, List<String>>{};

    for (var i = 0; i < responseHeaders.size(); i++) {
      final headerName = responseHeaders.name(i);
      final headerValue = responseHeaders.value(i);

      headers
          .putIfAbsent(
              headerName.toDartString(releaseOriginal: true).toLowerCase(),
              () => [])
          .add(headerValue.toDartString(releaseOriginal: true));
    }

    return headers.map((key, value) => MapEntry(key, value.join(',')));
  }

  bool _allowsRequestBody(String method) {
    return !(method == 'GET' || method == 'HEAD');
  }

  RequestBody _initRequestBody(String method, Uint8List body) {
    if (!_allowsRequestBody(method)) return RequestBody.fromRef(nullptr);

    return RequestBody.create2(MediaType.fromRef(nullptr), body.toJArray());
  }

  @override
  void close() {
    _isClosed = true;
    _kotlinBridge.release();
    super.close();
  }
}

extension on Uint8List {
  JArray<jbyte> toJArray() =>
      JArray(jbyte.type, length)..setRange(0, length, this);
}

extension on JArray<jbyte> {
  Uint8List toUint8List({int? length}) {
    length ??= this.length;
    final list = Uint8List(length);
    for (var i = 0; i < length; i++) {
      list[i] = this[i];
    }
    return list;
  }
}

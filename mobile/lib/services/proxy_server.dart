import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class LocalProxyServer {
  static HttpServer? _server;
  static String? _username;
  static int? get port => _server?.port;

  /// Starts the local proxy server on an available port.
  static Future<void> start(String username) async {
    _username = username;
    if (_server != null) return;
    
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    print('Proxy server running on localhost:\${_server!.port}');

    _server!.listen((HttpRequest request) async {
      try {
        final originalUrl = request.uri.queryParameters['url'];
        if (originalUrl == null) {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
          return;
        }

        // Determine correct base URL for relative proxying
        final uri = Uri.parse(originalUrl);
        final baseUrlStr = originalUrl.substring(0, originalUrl.lastIndexOf('/'));

        final response = await http.get(
          uri,
          headers: {
            'User-Agent': 'VanacueMobile/1.0',
            'Referer': 'https://vnc-e.com',
          },
        );

        request.response.headers.contentType = ContentType.parse(response.headers['content-type'] ?? 'application/vnd.apple.mpegurl');
        request.response.statusCode = response.statusCode;

        if (response.statusCode != 200) {
           request.response.add(response.bodyBytes);
           await request.response.close();
           return;
        }

        String body;
        try {
           body = latin1.decode(response.bodyBytes);
        } catch (e) {
           body = String.fromCharCodes(response.bodyBytes);
        }

        // Inject the ?u signature into all .m3u8 and .ts lines, or recursively route them through proxy
        List<String> lines = body.split('\n');
        for (int i = 0; i < lines.length; i++) {
          String line = lines[i].trim();
          
          // Strict ExoPlayer HLS Parser Fix: Remove undeclared SUBTITLES tags from EXT-X-STREAM-INF
          if (line.startsWith('#EXT-X-STREAM-INF:') && line.contains('SUBTITLES=')) {
              // Only remove SUBTITLES group if the playlist doesn't actually declare any SUBTITLES media
              if (!body.contains('#EXT-X-MEDIA:TYPE=SUBTITLES')) {
                  line = line.replaceAll(RegExp(r',SUBTITLES="[^"]+"'), '');
                  lines[i] = line;
              }
          }

          if (line.isNotEmpty && !line.startsWith('#')) {
             // It's a URI
             String newUri = line;
             if (!line.startsWith('http')) {
                // Handle relative paths accurately
                final baseUri = Uri.parse(baseUrlStr + '/');
                newUri = baseUri.resolve(line).toString();
             }
             
             // Ensure ?u= is present
             if (!newUri.contains('?u=')) {
                if (newUri.contains('?')) {
                    newUri = newUri + '&u=' + Uri.encodeComponent(_username!);
                } else {
                    newUri = newUri + '?u=' + Uri.encodeComponent(_username!);
                }
             }

             // If it's a child playlist (.m3u8), proxy it again
             if (newUri.contains('.m3u8')) {
                 lines[i] = 'http://127.0.0.1:' + _server!.port.toString() + '/?url=' + Uri.encodeComponent(newUri);
             } else {
                 lines[i] = newUri;
             }
          }
        }

        request.response.write(lines.join('\n'));
        await request.response.close();

      } catch (e) {
        print('Proxy Error: \$e');
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      }
    });
  }

  static void stop() {
    _server?.close();
    _server = null;
  }
}

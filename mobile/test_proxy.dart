import 'dart:io';
import 'dart:convert';
import 'lib/services/proxy_server.dart';

void main() async {
  print('Starting proxy...');
  await LocalProxyServer.start('Aaron');
  
  final proxyPort = LocalProxyServer.port.toString();
  final targetUrl = 'https://vnc-e.com/peliculas/Th_Kllr-2023/master.m3u8';
  final encodedTargetUrl = Uri.encodeComponent(targetUrl);
  
  final localUrl = 'http://127.0.0.1:' + proxyPort + '/?url=' + encodedTargetUrl;
  print('Targeting: ' + localUrl);
  
  var httpClient = HttpClient();
  var request = await httpClient.getUrl(Uri.parse(localUrl));
  var response = await request.close();
  
  var body = await response.transform(utf8.decoder).join();
  print('--- PROXY RESPONSE ---');
  print(body);
  print('--- END ---');
  
  LocalProxyServer.stop();
  exit(0);
}

import 'dart:io';
import 'dart:convert';

void main() async {
  final urlStr = 'https://vnc-e.com/peliculas/Th_Kllr-2023/master.m3u8?u=Aaron';
  
  try {
    var httpClient = HttpClient();
    var request = await httpClient.getUrl(Uri.parse(urlStr));
    request.headers.set('User-Agent', 'VanacueMobile/1.0');
    request.headers.set('Referer', 'https://vnc-e.com');
    
    var response = await request.close();
    var body = await response.transform(utf8.decoder).join();
    print('--- M3U8 CONTENT ---');
    print(body);
    print('--- END ---');
  } catch (e) {
    print('Error: \$e');
  }
}

import 'dart:io';

void main() async {
  final urlStr = 'https://vnc-e.com/peliculas/Th_Kllr-2023/master.m3u8?u=Aaron';
  print('Testing: ' + urlStr);
  
  try {
    var httpClient = HttpClient();
    var request = await httpClient.getUrl(Uri.parse(urlStr));
    
    // Simulate ExoPlayer Headers
    request.headers.set('User-Agent', 'VanacueMobile/1.0');
    request.headers.set('Referer', 'https://vnc-e.com');
    
    var response = await request.close();
    
    print('Status: ' + response.statusCode.toString());
    print('Headers: ' + response.headers.toString());
  } catch (e) {
    print('Error: ' + e.toString());
  }
}

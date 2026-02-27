for f in ['lib/widgets/movie_detail_modal.dart', 'lib/widgets/series_detail_modal.dart']:
    with open(f, 'r', encoding='utf-8') as fh:
        content = fh.read()
    if 'url_launcher' not in content:
        content = content.replace(
            "import 'package:share_plus/share_plus.dart';",
            "import 'package:url_launcher/url_launcher.dart';\nimport 'package:share_plus/share_plus.dart';"
        )
        with open(f, 'w', encoding='utf-8') as fh:
            fh.write(content)
        print(f'Added url_launcher import to {f}')
    else:
        print(f'{f} already has url_launcher import')

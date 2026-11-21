"""CC0 solid 4000x4000 PNG/JPEG for the bounded reader decoder campaign."""
from pathlib import Path
from PIL import Image
import base64
import io
import json

root = Path(__file__).resolve().parents[3]
lines = ['// CC0 generated solid images; test-only, never a production asset.']
for fmt in ('PNG', 'JPEG'):
    stream = io.BytesIO()
    Image.new('RGB', (4000, 4000), (30, 70, 90)).save(stream, format=fmt)
    lines.append('const readerLarge' + fmt.title() + ' = ' +
                 json.dumps(base64.b64encode(stream.getvalue()).decode()) + ';')
(root / 'integration_test/epub_reader_images.dart').write_text('\n'.join(lines) + '\n')

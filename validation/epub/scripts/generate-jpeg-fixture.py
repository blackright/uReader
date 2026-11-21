"""CC0 synthetic 2x2 grayscale baseline JPEG, standard-library only; no source image."""
from pathlib import Path
import base64
import hashlib
import json
import struct

ROOT = Path(__file__).resolve().parents[3]


def jpeg():
    def segment(marker, payload):
        return b'\xff' + bytes([marker]) + struct.pack('>H',len(payload)+2) + payload
    counts = bytes([1]+[0]*15)
    tables = b'\0'+counts+b'\0'+b'\x10'+counts+b'\0'
    return (b'\xff\xd8' + segment(0xe0,b'JFIF\0\x01\x01\0\0\x01\0\x01\0\0')
            + segment(0xdb,b'\0'+bytes([1]*64))
            + segment(0xc0,bytes([8])+struct.pack('>HH',2,2)+bytes([1,1,0x11,0]))
            + segment(0xc4,tables) + segment(0xda,bytes([1,1,0,0,63,0]))
            + b'\x3f\xff\xd9')


if __name__ == '__main__':
    data = jpeg()
    text = '// Generated CC0 synthetic JPEG. Regenerate with generate-jpeg-fixture.py.\n'
    text += 'const gateJpegBase64 = '+json.dumps(base64.b64encode(data).decode())+';\n'
    file = ROOT/'integration_test/epub_gate_jpeg.dart'
    if file.exists() and file.read_text() != text:
        raise ValueError('Preserve changed generated JPEG fixture')
    file.write_text(text)
    (ROOT/'validation/epub/reports/jpeg-fixture.json').write_text(json.dumps({
        'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),
        'width':2,'height':2,'rights':'CC0-1.0, generated without a source image',
        'androidDecode':'not_evaluated'},indent=2)+'\n')
    print('Generated deterministic 2x2 JPEG fixture')

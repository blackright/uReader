"""Export the verified local Kokoro weights; never download models or replace a bundle."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import socket
import time

ROOT = Path(__file__).resolve().parents[3]


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def token_ids(phonemes, vocab):
    if not isinstance(phonemes, str) or not 0 < len(phonemes) <= 510:
        raise ValueError('Phoneme length outside model context')
    if any(c not in vocab for c in phonemes):
        raise ValueError('Unknown phoneme; refusing silent omission')
    return [0, *(vocab[c] for c in phonemes), 0]


def verified_candidate():
    manifest = json.loads((ROOT / 'specs/004-french-narration-quality/candidate-files.json').read_text(encoding='utf-8'))
    candidate = next(c for c in manifest['candidates'] if c['candidateId'] == 'kokoro-siwis')
    directory = ROOT / candidate['directory']
    for entry in candidate['downloadFiles']:
        path = directory / entry['relativePath']
        if path.stat().st_size != entry['byteSize'] or sha(path) != entry['sha256']:
            raise ValueError('Candidate file integrity failure')
    return directory, candidate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    private = (ROOT / 'validation/reader/private').resolve()
    if not args.output.resolve().is_relative_to(private):
        raise ValueError('Private output required')
    directory, candidate = verified_candidate()
    args.output.mkdir(parents=True, exist_ok=False)
    report = {'status': 'initializing', 'modelSource': candidate['downloadFiles'],
              'networkBlocked': True, 'mobileQualified': False}
    index = args.output / 'export-report.json'

    def save():
        index.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')

    os.environ.update(HF_HUB_OFFLINE='1', HF_HUB_DISABLE_TELEMETRY='1',
                      TRANSFORMERS_OFFLINE='1', DO_NOT_TRACK='1')

    def no_network(*args, **kwargs):
        raise RuntimeError('Network disabled during export')

    socket.socket.connect = no_network
    socket.create_connection = no_network
    save()
    try:
        print('Loading local export dependencies', flush=True)
        import numpy as np
        import onnx
        import onnxruntime as ort
        import torch
        from kokoro.model import KModel, KModelForONNX
        print('Loading verified Kokoro weights', flush=True)
        torch.set_num_threads(1)
        torch.manual_seed(7601)
        model = KModel(repo_id='hexgrad/Kokoro-82M', config=str(directory / 'config.json'),
                       model=str(directory / 'kokoro-v1_0.pth'), disable_complex=True).eval()
        voice = torch.load(directory / 'ff_siwis.pt', map_location='cpu', weights_only=True)
        baseline = json.loads((private / 'french-narration-20261125-phase3/kokoro-siwis-T01/index.json').read_text(encoding='utf-8'))
        probes = [row for row in baseline['segments'] if row['paragraphId'] == 'P05']
        first = probes[0]
        ids = torch.tensor([token_ids(first['phonemes'], model.vocab)], dtype=torch.long)
        style = voice[len(first['phonemes']) - 1]
        speed = torch.tensor(1.0, dtype=torch.float32)
        report.update(status='exporting', torchVersion=torch.__version__,
                      onnxVersion=onnx.__version__, ortVersion=ort.__version__, opset=17)
        save()
        target = args.output / 'kokoro.onnx'
        print('Exporting ONNX graph', flush=True)
        started = time.monotonic()
        with torch.no_grad():
            torch.onnx.export(KModelForONNX(model), (ids, style, speed), str(target),
                              input_names=['input_ids', 'ref_s', 'speed'],
                              output_names=['waveform', 'duration'],
                              dynamic_axes={'input_ids': {1: 'phonemes'},
                                            'waveform': {0: 'samples'},
                                            'duration': {0: 'phonemes'}},
                              opset_version=17, dynamo=False)
        report.update(status='checking', exportSeconds=time.monotonic() - started)
        save()
        print('Checking ONNX graph and dynamic-length probes', flush=True)
        onnx.checker.check_model(str(target))
        options = ort.SessionOptions()
        options.intra_op_num_threads = 1
        options.inter_op_num_threads = 1
        session = ort.InferenceSession(str(target), sess_options=options, providers=['CPUExecutionProvider'])
        report['inputs'] = [{'name': x.name, 'shape': x.shape, 'type': x.type} for x in session.get_inputs()]
        report['outputs'] = [{'name': x.name, 'shape': x.shape, 'type': x.type} for x in session.get_outputs()]
        report['probes'] = []
        for probe in probes:
            phones = probe['phonemes']
            values = {'input_ids': np.asarray([token_ids(phones, model.vocab)], dtype=np.int64),
                      'ref_s': voice[len(phones) - 1].numpy(), 'speed': np.array(1, dtype=np.float32)}
            start = time.monotonic()
            audio, durations = session.run(None, values)
            audio = audio.reshape(-1)
            if not 0 < audio.size <= 480000 or not np.isfinite(audio).all() or not np.any(audio):
                raise ValueError('Invalid or oversized native candidate audio')
            if durations.size != len(phones) + 2 or np.any(durations < 1):
                raise ValueError('Duration/token contract mismatch')
            import wave
            name = probe['id'] + '.wav'
            with wave.open(str(args.output / name), 'wb') as wav:
                wav.setparams((1, 2, 24000, 0, 'NONE', 'not compressed'))
                wav.writeframes((np.clip(audio, -1, 1) * 32767).astype('<i2').tobytes())
            report['probes'].append({'id': probe['id'], 'phonemes': len(phones),
                                      'samples': int(audio.size), 'wav': name,
                                      'generationSeconds': time.monotonic() - start,
                                      'sha256': sha(args.output / name)})
            save()
        # Store plain numeric data for Android; never load PyTorch pickles in the app.
        voice.numpy().astype('<f4').tofile(args.output / 'siwis.f32')
        (args.output / 'vocab.json').write_text(json.dumps(model.vocab, ensure_ascii=False), encoding='utf-8')
        report.update(status='exported_pc_probes_passed', modelSha256=sha(target),
                      modelBytes=target.stat().st_size, voiceShape=list(voice.shape),
                      perceptualParity='not_evaluated')
    except BaseException as error:
        report.update(status='failed', failureType=type(error).__name__, failureMessage=str(error)[:500])
        raise
    finally:
        save()


if __name__ == '__main__':
    main()

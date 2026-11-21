"""Stock-3.3.0 artifact selection, local paths only; no comparison with an older export."""
import argparse
import hashlib
import importlib.metadata
import importlib.resources
import importlib.util
import json
import os
from pathlib import Path
import socket
import time
import wave

os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['HF_HUB_DISABLE_TELEMETRY'] = '1'
os.environ['DO_NOT_TRACK'] = '1'
os.environ['KPOCKET_TTS_ERROR_WITHOUT_EOS'] = '1'


def offline(*args, **kwargs):
    raise RuntimeError('Network forbidden during aligned reference')


socket.socket.connect = socket.socket.connect_ex = socket.create_connection = socket.getaddrinfo = offline

import numpy as np
import torch
import yaml
from pocket_tts import TTSModel
from pocket_tts.models.text_chunking import prepare_text_prompt, split_into_best_sentences
from pocket_tts.utils.utils import get_predefined_voice


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def run(passage_id, wav_path, max_tokens_per_chunk=50, numbers_in_words=False,
        normalized_cases=None, case_id=None, join_twenty_one=False):
    root = Path(__file__).resolve().parents[2]
    lock = json.loads((root / 'validation/reference-3.3-aligned-lock.json').read_text())
    original_lock = json.loads((root / 'validation/model-lock.json').read_text(encoding='utf-8'))
    directory = root / lock['directory']
    spec = importlib.util.spec_from_file_location('verifier', Path(__file__).with_name('verify-model-files.py'))
    verifier = importlib.util.module_from_spec(spec); spec.loader.exec_module(verifier)
    errors = verifier.verify(directory, lock['downloadFiles'])
    tokenizer_root = root / 'validation/private/models/fr-6l'
    tokenizer_entry = next(e for e in original_lock['downloadFiles'] if e['relativePath'] == 'tokenizer.json')
    errors += verifier.verify(tokenizer_root, [tokenizer_entry])
    if errors: raise ValueError('; '.join(errors))
    if importlib.metadata.version('pocket-tts') != '3.3.0': raise ValueError('Pinned official package required')
    package = importlib.resources.files('pocket_tts')
    config_bytes = package.joinpath('config/french.yaml').read_bytes()
    utils_bytes = package.joinpath('utils/utils.py').read_bytes()
    assert hashlib.sha256(config_bytes).hexdigest() == lock['sourceEvidence']['frenchConfigSha256']
    assert hashlib.sha256(utils_bytes).hexdigest() == lock['sourceEvidence']['voiceResolverSourceSha256']
    config = yaml.safe_load(config_bytes.decode('utf-8'))
    assert config['weights_path_without_voice_cloning'].endswith('@8843db76457a91db32077edf8dfcd1c0e3e755fd')
    voice_uri = get_predefined_voice('french', 'estelle')
    assert voice_uri.endswith('@4e1e0a3e611c51c0b4ed8174fc10f32a54644303')
    config['weights_path'] = str((directory / 'model.safetensors').resolve())
    config['weights_path_without_voice_cloning'] = None
    config['flow_lm']['lookup_table']['tokenizer_path'] = str((tokenizer_root / 'tokenizer.json').resolve())
    encoded = yaml.safe_dump(config, allow_unicode=False)
    local_config = directory / ('aligned-local-' + hashlib.sha256(encoded.encode('ascii')).hexdigest()[:12] + '.yaml')
    if local_config.exists():
        assert local_config.read_text(encoding='ascii') == encoded
    else:
        with local_config.open('x', encoding='ascii') as handle: handle.write(encoded)
    torch.set_num_threads(1)
    torch.manual_seed(0)
    model = TTSModel.load_model(config=local_config, temp=.3, sampler_decode_steps=1, eos_threshold=-4)
    voice = model.get_state_for_audio_prompt(directory / 'estelle.safetensors')
    corpus_bytes = (root / 'assets/corpus/fr_demo.json').read_bytes()
    passage = next(p for t in json.loads(corpus_bytes)['texts'] for p in t['passages'] if p['id'] == passage_id)
    text = passage['text'].split('.', 1)[0] + '.'
    source_text = text
    normalized_evidence = None
    if normalized_cases is not None:
        if numbers_in_words:
            raise ValueError('Choose one text transformation')
        cases = json.loads(normalized_cases.read_text(encoding='utf-8'))
        if cases['normalizerVersion'] not in ('fr-numbers-v1', 'fr-numbers-v2', 'fr-numbers-v3'):
            raise ValueError('Unexpected normalizer version')
        case = next(c for c in cases['cases'] if c['id'] == case_id)
        source_text, text = case['sourceText'], case['synthesisText']
        if case_id in ('fr-01-p1', 'fr-04-p1'):
            original = next(p for t in json.loads(corpus_bytes)['texts'] for p in t['passages'] if p['id'] == case_id)
            if source_text != original['text'].split('.', 1)[0] + '.':
                raise ValueError('Protocol fixture differs from corpus extract')
        if not source_text or not text or len(text) > 1000:
            raise ValueError('Invalid diagnostic fixture')
        normalizer_path = root / 'lib/features/listening/french_text_normalizer.dart'
        normalized_evidence = {'caseId': case_id, 'casesSha256': sha(normalized_cases),
            'normalizerVersion': cases['normalizerVersion'],
            'normalizerSourceSha256': sha(normalizer_path), 'spans': case['spans']}
    if join_twenty_one:
        if normalized_evidence is None or case_id != 'agreements' or text.count('vingt et un') != 1:
            raise ValueError('Hyphen diagnostic requires the single agreements fixture')
        before = text
        text = text.replace('vingt et un', 'vingt-et-un')
        assert len(before.encode('utf-16-le')) == len(text.encode('utf-16-le'))
        normalized_evidence['postNormalizationDiagnostic'] = {
            'replacement': 'vingt et un -> vingt-et-un',
            'baselineSynthesisTextSha256': hashlib.sha256(before.encode()).hexdigest(),
            'utf16LengthsUnchanged': True, 'productionNormalizerChanged': False}
    if numbers_in_words:
        if passage_id != 'fr-05-p1':
            raise ValueError('Numbers-in-words diagnostic is restricted to fr-05-p1')
        # Explicit experimental fixture, not a general-purpose normalization rule.
        text = ('Le douze avril deux mille vingt-six, à neuf heures trente, '
                'nous achetons trois pommes, deux poires et deux cent cinquante grammes de fromage.')
    prepared, _ = prepare_text_prompt(text, False, True, replace_characters=config['replace_characters'])
    ids = model.flow_lm.conditioner.prepare(prepared).reshape(-1).tolist()
    if not 1 <= len(ids) <= (100 if numbers_in_words or normalized_evidence else 50):
        raise ValueError('Diagnostic token limit exceeded')
    chunks = split_into_best_sentences(model.flow_lm.conditioner.tokenizer, text,
        max_tokens_per_chunk, False, True, replace_characters=config['replace_characters'])
    # The experiment changes boundaries only, not the source words or quantities.
    if ''.join(''.join(chunks).split()) != ''.join(prepared.split()):
        raise ValueError('Official chunking changed source content')
    torch.manual_seed(0)
    start = time.monotonic()
    # The official streaming API mutates state from background threads. no_grad
    # preserves ordinary tensors; inference_mode would make those updates invalid.
    with torch.no_grad():
        audio = model.generate_audio(voice, text, max_tokens=max_tokens_per_chunk).numpy().reshape(-1)
    elapsed = time.monotonic() - start
    if model.sample_rate != 24000 or not 0 < audio.size <= 480000 or not np.isfinite(audio).all() or not np.any(audio != 0):
        raise ValueError('Invalid or unbounded reference PCM')
    with wav_path.open('xb') as raw:
        with wave.open(raw, 'wb') as handle:
            handle.setnchannels(1); handle.setsampwidth(2); handle.setframerate(24000)
            handle.writeframes((np.clip(audio, -1, 1) * 32767).astype('<i2').tobytes())
    return {'status': 'generated_listening_pending', 'scope': 'Official 3.3.0 default no-cloning weights and Estelle selection; PC only',
            'passageId': passage_id, 'sourceTextSha256': hashlib.sha256(source_text.encode()).hexdigest(),
            'sourceText': source_text, 'synthesisText': text,
            'textTransformation': 'dart_normalizer_plus_hyphen_diagnostic' if join_twenty_one else 'dart_normalizer_diagnostic' if normalized_evidence else 'manual_numbers_in_words_diagnostic' if numbers_in_words else 'none',
            'normalizationEvidence': normalized_evidence,
            'productionNormalizationImplemented': False,
            'preparedTextSha256': hashlib.sha256(prepared.encode()).hexdigest(),
            'corpusSha256': hashlib.sha256(corpus_bytes).hexdigest(), 'endOffsetUtf16': len(source_text.encode('utf-16-le')) // 2,
            'versions': {name: importlib.metadata.version(name) for name in ['pocket-tts', 'torch', 'numpy', 'tokenizers', 'safetensors']},
            'weightsSha256': sha(directory / 'model.safetensors'), 'voiceSha256': sha(directory / 'estelle.safetensors'),
            'tokenizerSha256': sha(tokenizer_root / 'tokenizer.json'), 'scriptSha256': sha(Path(__file__)),
            'voiceOffsets': {name: int(state['offset'].item()) for name, state in voice.items() if 'offset' in state},
            'seed': 0, 'tokenIds': ids, 'maxTokensPerChunk': max_tokens_per_chunk,
            'chunks': [{'textSha256': hashlib.sha256(chunk.encode()).hexdigest(),
                        'tokenIds': model.flow_lm.conditioner.prepare(chunk).reshape(-1).tolist()} for chunk in chunks],
            'sourceContentPreserved': text == source_text,
            'synthesisContentPreservedByChunking': True,
            'samples': int(audio.size), 'sampleRate': 24000,
            'durationSeconds': audio.size / 24000, 'generationSeconds': elapsed,
            'wav': wav_path.as_posix(), 'wavSha256': sha(wav_path), 'intelligibility': 'not_evaluated',
            'pythonNetworkBlocked': True, 'androidExecuted': False, 'g0': 'not_demonstrated'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--passage-id', choices=['fr-01-p1', 'fr-04-p1', 'fr-05-p1'], default='fr-05-p1')
    parser.add_argument('--wav', required=True, type=Path)
    parser.add_argument('--report', required=True, type=Path)
    parser.add_argument('--max-tokens-per-chunk', type=int, choices=[20, 50], default=50)
    parser.add_argument('--numbers-in-words', action='store_true', help='PC-only manual fixture; not a production normalizer')
    parser.add_argument('--normalized-cases', type=Path)
    parser.add_argument('--case-id', choices=['numbers', 'agreements', 'leap-year', 'fr-01-p1', 'fr-04-p1'])
    parser.add_argument('--join-twenty-one', action='store_true', help='PC diagnostic only: vingt et un -> vingt-et-un')
    args = parser.parse_args()
    if args.wav.exists() or args.report.exists(): parser.error('New output files required')
    if bool(args.normalized_cases) != bool(args.case_id):
        parser.error('--normalized-cases and --case-id must be provided together')
    result = run(args.passage_id, args.wav, args.max_tokens_per_chunk, args.numbers_in_words,
        args.normalized_cases, args.case_id, args.join_twenty_one)
    if args.normalized_cases:
        result['passageId'] = args.case_id if args.case_id.startswith('fr-') else None
        if not args.case_id.startswith('fr-'):
            result['corpusSha256'] = None
    with args.report.open('x', encoding='utf-8') as handle: json.dump(result, handle, indent=2); handle.write('\n')
    print(json.dumps({key: result[key] for key in ['status', 'samples', 'durationSeconds', 'generationSeconds']}))

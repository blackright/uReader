"""Essai ONNX CPU de laboratoire ; pas une référence Python officielle ou une preuve G0."""

import argparse
import hashlib
import importlib.metadata
import importlib.util
import json
import math
from pathlib import Path
import time
import wave

import numpy as np
import onnxruntime as ort
from tokenizers import Tokenizer


def run(directory, wav_path, lock_file=None, passage_id="fr-01-p1", no_optimizations=False):
    spec = importlib.util.spec_from_file_location(
        "inspect_onnx", Path(__file__).with_name("inspect-onnx.py"))
    inspector = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(inspector)
    inspection = inspector.inspect(directory, lock_file)
    manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
    # Segment figé du corpus : début du premier passage, jusqu'au premier point.
    corpus_path = Path(__file__).resolve().parents[2] / "assets/corpus/fr_demo.json"
    corpus_bytes = corpus_path.read_bytes()
    passage = next(p for t in json.loads(corpus_bytes)["texts"] for p in t["passages"] if p["id"] == passage_id)
    text = passage["text"].split(".", 1)[0] + "."
    prepared = " ".join(text.translate(str.maketrans(manifest["replace_characters"])).split())
    if manifest["remove_semicolons"]:
        prepared = prepared.replace(";", ",")
    ids = Tokenizer.from_file(str(directory / "tokenizer.json")).encode(prepared).ids
    if not 1 <= len(ids) <= 50 or manifest["sampler_decode_steps"] != 1:
        raise ValueError("Segment ou nombre d'étapes hors protocole de cet essai.")
    table = np.fromfile(directory / "text_embeddings.f16", dtype="<f2").reshape(4001, 1024)
    voice = np.fromfile(directory / "voices/estelle.f16", dtype="<f2")
    if not np.isfinite(table).all() or not np.isfinite(voice).all():
        raise ValueError("État ou embeddings non finis.")
    options = ort.SessionOptions()
    options.intra_op_num_threads = 1
    options.inter_op_num_threads = 1
    if no_optimizations:
        options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_DISABLE_ALL
    sessions = {name: ort.InferenceSession(str(directory / file), options,
                providers=["CPUExecutionProvider"])
                for name, file in manifest["models"].items()}
    states, cursor = {}, 0
    for index, offset in enumerate(manifest["voices"]["estelle"]["offsets"]):
        shape = (2, 1, offset, 16, 64)
        count = math.prod(shape)
        states[f"cache_{index}"] = voice[cursor:cursor + count].reshape(shape).astype(np.float32)
        states[f"offset_{index}"] = np.array([offset], dtype=np.int64)
        cursor += count
    if cursor != voice.size or len(states) != 12:
        raise ValueError("Disposition de voix incompatible.")
    main, flow, decoder = (sessions[n] for n in ("flow_lm_main", "flow_lm_flow", "mimi_decoder"))

    def main_step(sequence, embeddings):
        outputs = main.run(None, {"sequence": sequence, "text_embeddings": embeddings, **states})
        for index in range(6):
            states[f"cache_{index}"] = outputs[2 + 2 * index]
            states[f"offset_{index}"] = outputs[3 + 2 * index]
        if not np.isfinite(outputs[0]).all() or not np.isfinite(outputs[1]).all():
            raise ValueError("Sortie principale non finie.")
        return outputs[0], float(outputs[1].item())

    start = time.monotonic()
    main_step(np.empty((1, 0, 32), np.float32), table[ids][None].astype(np.float32))
    empty = np.empty((1, 0, 1024), np.float32)
    sequence = np.full((1, 1, 32), np.nan, np.float32)
    rng = np.random.default_rng(0)
    latents, eos_at = [], None
    limit = min(250, math.ceil((len(ids) / 3.0 + 2.0) * 12.5))
    tail = (3 if len(prepared.split()) <= 4 else 1) + 2
    for step in range(limit):
        if time.monotonic() - start > 120:
            raise ValueError("Budget de temps dépassé ; aucune preuve de terminaison.")
        conditioning, eos = main_step(sequence, empty)
        if step >= manifest["min_frames_before_eos"] and eos > manifest["eos_threshold"] and eos_at is None:
            eos_at = step
        if eos_at is not None and step >= eos_at + tail:
            break
        noise = rng.normal(0, math.sqrt(manifest["temperature"]), (1, 32)).astype(np.float32)
        direction = flow.run(None, {"c": conditioning, "s": np.zeros((1, 1), np.float32),
                                  "t": np.ones((1, 1), np.float32), "x": noise})[0]
        sequence = (noise + direction).reshape(1, 1, 32)
        if not np.isfinite(sequence).all():
            raise ValueError("Latent non fini.")
        latents.append(sequence)
    if eos_at is None or step < eos_at + tail or not latents:
        raise ValueError("EOS non atteint et finalisé dans la borne : essai non concluant.")
    generation_seconds = time.monotonic() - start
    mimi = {f"mimi_{i}": (np.ones if e["key"] == "first" else np.zeros)(
            e["shape"], dtype={"float32": np.float32, "int64": np.int64, "bool": np.bool_}[e["dtype"]])
            for i, e in enumerate(manifest["mimi_states"])}
    audio = []
    for chunk in range(0, len(latents), 12):
        outputs = decoder.run(None, {"latent": np.concatenate(latents[chunk:chunk + 12], axis=1), **mimi})
        audio.append(outputs[0].reshape(-1))
        mimi = {f"mimi_{i}": value for i, value in enumerate(outputs[1:])}
    samples = np.concatenate(audio)
    if (not np.isfinite(samples).all() or not 0 < samples.size <= 480000
            or not np.any(samples != 0)):
        raise ValueError("PCM vide, non fini, silencieux ou hors borne.")
    wav_path.parent.mkdir(parents=True, exist_ok=True)
    with wav_path.open("xb") as raw:
        with wave.open(raw, "wb") as handle:
            handle.setnchannels(1)
            handle.setsampwidth(2)
            handle.setframerate(24000)
            handle.writeframes((np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes())
    return {"schemaVersion": 1, "trial": "onnx_cpu_smoke_not_official_reference",
            "candidateRevision": inspection["candidateRevision"],
            "optimization": "disabled" if no_optimizations else "runtime_default",
            "versions": {name: importlib.metadata.version(name) for name in
                         ("onnx", "onnxruntime", "numpy", "tokenizers")},
            "corpusSha256": hashlib.sha256(corpus_bytes).hexdigest(),
            "passageId": passage["id"], "startOffsetUtf16": 0,
            "endOffsetUtf16": len(text.encode("utf-16-le")) // 2,
            "textSha256": hashlib.sha256(text.encode()).hexdigest(),
            "tokenIds": ids, "tokens": len(ids), "seed": 0, "frames": len(latents),
            "eosAtFrame": eos_at, "frameLimit": limit,
            "generationSeconds": generation_seconds,
            "generationAndDecodeSeconds": time.monotonic() - start,
            "samples": int(samples.size), "sampleRate": 24000,
            "durationSeconds": samples.size / 24000,
            "pcmPeakBeforeClipping": float(np.abs(samples).max()),
            "clippedSamples": int(np.count_nonzero(np.abs(samples) > 1)),
            "wavSha256": hashlib.sha256(wav_path.read_bytes()).hexdigest(),
            "officialReferenceCompared": False, "intelligibility": "not_evaluated",
            "androidExecuted": False, "g0": "not_demonstrated"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--wav", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--lock-file", type=Path, help="Explicit lab audit lock; does not activate a product bundle")
    parser.add_argument("--passage-id", choices=["fr-01-p1", "fr-04-p1", "fr-05-p1"], default="fr-01-p1")
    parser.add_argument("--no-optimizations", action="store_true")
    args = parser.parse_args()
    if args.report.exists() or args.wav.exists():
        parser.error("Choisir de nouveaux fichiers pour préserver les preuves précédentes.")
    report = run(args.directory, args.wav, args.lock_file, args.passage_id, args.no_optimizations)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    with args.report.open("x", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print("WAV ONNX CPU généré avec EOS ; intelligibilité et G0 non évalués.")

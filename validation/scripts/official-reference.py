"""Référence Pocket TTS 3.3.0 sur poste, avec ressources locales et réseau interdit."""

import argparse
import copy
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

os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
os.environ["DO_NOT_TRACK"] = "1"


def deny_network(*args, **kwargs):
    raise RuntimeError("Réseau interdit pendant la référence locale.")


socket.socket.connect = deny_network
socket.socket.connect_ex = deny_network
socket.create_connection = deny_network
socket.getaddrinfo = deny_network

import numpy as np
import onnxruntime as ort
import torch
import yaml


def metrics(reference, actual):
    a = np.asarray(reference, dtype=np.float64).reshape(-1)
    b = np.asarray(actual, dtype=np.float64).reshape(-1)
    if a.shape != b.shape or not np.isfinite(a).all() or not np.isfinite(b).all():
        raise ValueError("Sorties non finies ou de tailles différentes.")
    delta = a - b
    return {"elements": a.size, "maxAbsoluteError": float(np.abs(delta).max()),
            "rmse": float(np.sqrt(np.mean(delta ** 2))),
            "referenceRms": float(np.sqrt(np.mean(a ** 2)))}


def run(reference_dir, onnx_dir, wav_path, passage_id="fr-01-p1", audit_lock=None):
    root = Path(__file__).resolve().parents[2]
    lock = json.loads((root / "validation/model-lock.json").read_text(encoding="utf-8"))
    spec = importlib.util.spec_from_file_location(
        "verify_files", Path(__file__).with_name("verify-model-files.py"))
    verifier = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(verifier)
    candidate_lock = json.loads(audit_lock.read_text(encoding="utf-8")) if audit_lock else lock
    for directory, entries in [(reference_dir, lock["officialReference"]["downloadFiles"]),
                               (onnx_dir, candidate_lock["downloadFiles"])]:
        errors = verifier.verify(directory, entries)
        if errors:
            raise ValueError("; ".join(errors))
    if importlib.metadata.version("pocket-tts") != "3.3.0":
        raise ValueError("Pocket TTS 3.3.0 requis.")
    from pocket_tts import TTSModel
    from pocket_tts.models.text_chunking import prepare_text_prompt
    from pocket_tts.modules.stateful_module import increment_steps, init_states

    torch.set_num_threads(1)
    torch.manual_seed(0)
    config_source = importlib.resources.files("pocket_tts").joinpath("config/french.yaml")
    config = yaml.safe_load(config_source.read_text(encoding="utf-8"))
    config["weights_path"] = str((reference_dir / "model.safetensors").resolve())
    config["weights_path_without_voice_cloning"] = None
    config["flow_lm"]["lookup_table"]["tokenizer_path"] = str((onnx_dir / "tokenizer.json").resolve())
    # Pocket TTS 3.3.0 ouvre le YAML avec l'encodage Windows par défaut.
    # Échapper les caractères Unicode conserve les valeurs sans modifier l'amont.
    encoded_config = yaml.safe_dump(config, allow_unicode=False)
    config_digest = hashlib.sha256(encoded_config.encode("ascii")).hexdigest()[:12]
    local_config = reference_dir / f"official-local-{config_digest}.yaml"
    if local_config.exists():
        if local_config.read_text(encoding="utf-8") != encoded_config:
            raise ValueError("Une configuration locale différente existe déjà.")
    else:
        local_config.write_text(encoded_config, encoding="utf-8")
    model = TTSModel.load_model(config=local_config, temp=0.3, sampler_decode_steps=1,
                               eos_threshold=-4.0)
    voice = model.get_state_for_audio_prompt(reference_dir / "estelle.safetensors")
    manifest = json.loads((onnx_dir / "manifest.json").read_text(encoding="utf-8"))
    corpus_bytes = (root / "assets/corpus/fr_demo.json").read_bytes()
    passage = next((p for t in json.loads(corpus_bytes)["texts"] for p in t["passages"]
                    if p["id"] == passage_id), None)
    if passage is None or passage_id not in {"fr-01-p1", "fr-04-p1", "fr-05-p1"}:
        raise ValueError("Passage hors protocole G0.")
    text = passage["text"].split(".", 1)[0] + "."
    prepared, _ = prepare_text_prompt(text, False, True,
                                      replace_characters=manifest["replace_characters"])
    lm = model.flow_lm
    tokens = lm.conditioner.prepare(prepared)
    from tokenizers import Tokenizer
    ids = tokens.reshape(-1).tolist()
    if ids != Tokenizer.from_file(str(onnx_dir / "tokenizer.json")).encode(prepared).ids:
        raise ValueError("Les tokens officiels diffèrent de l'essai ONNX.")
    if not 1 <= len(ids) <= 50:
        raise ValueError("Segment G0 hors limite de tokens.")
    table = np.fromfile(onnx_dir / "text_embeddings.f16", dtype="<f2").reshape(4001, 1024)
    table_matches = np.array_equal(table, lm.conditioner.embed.weight.detach().numpy().astype(np.float16))
    compact_voice = np.fromfile(onnx_dir / "voices/estelle.f16", dtype="<f2")
    states, cursor, voice_matches = {}, 0, True
    for index, entry in enumerate(manifest["flow_layers"]):
        layer = voice[entry["name"]]
        offset = int(layer["offset"].item())
        shape = (2, 1, offset, entry["heads"], entry["head_dim"])
        size = int(np.prod(shape))
        compact = compact_voice[cursor:cursor + size].reshape(shape)
        original = layer["cache"][:, :, :offset].numpy()
        voice_matches = voice_matches and np.array_equal(compact, original.astype(np.float16))
        states[f"cache_{index}"] = compact.astype(np.float32)
        states[f"offset_{index}"] = np.array([offset], np.int64)
        cursor += size
    if not table_matches or not voice_matches or cursor != compact_voice.size:
        raise ValueError("Embeddings ou voix FP16 différents de la source officielle.")

    options = ort.SessionOptions()
    options.intra_op_num_threads = 1
    options.inter_op_num_threads = 1
    sessions = {name: ort.InferenceSession(str(onnx_dir / file), options,
                providers=["CPUExecutionProvider"]) for name, file in manifest["models"].items()}
    with torch.no_grad():
        state = copy.deepcopy(voice)
        model._expand_kv_cache(state, model._flow_lm_current_end(state) + len(ids) + 4)
        empty = torch.empty(1, 0, 32)
        embeddings = lm.conditioner(tokens)
        lm.backbone(lm.input_linear(empty), embeddings, empty, model_state=state)
        increment_steps(lm, state, len(ids))
        bos = lm.bos_emb.expand(1, 1, 32)
        hidden = lm.backbone(lm.input_linear(bos), torch.empty(1, 0, 1024), bos,
                             model_state=state).float()[:, -1]
        eos = lm.out_eos(hidden)
        main = sessions["flow_lm_main"]
        prefill = main.run(None, {"sequence": np.empty((1, 0, 32), np.float32),
                                "text_embeddings": table[ids][None].astype(np.float32), **states})
        for index in range(6):
            states[f"cache_{index}"] = prefill[2 + 2 * index]
            states[f"offset_{index}"] = prefill[3 + 2 * index]
        first = main.run(None, {"sequence": np.full((1, 1, 32), np.nan, np.float32),
                               "text_embeddings": np.empty((1, 0, 1024), np.float32), **states})
        noise = np.random.default_rng(0).normal(0, np.sqrt(0.3), (1, 32)).astype(np.float32)
        flow_ref = lm.flow_net(hidden, torch.zeros(1, 1), torch.ones(1, 1), torch.from_numpy(noise))
        flow_out = sessions["flow_lm_flow"].run(None, {"c": hidden.numpy(),
                   "s": np.zeros((1, 1), np.float32), "t": np.ones((1, 1), np.float32), "x": noise})[0]
        comparisons = {"firstStepConditioning": metrics(hidden.numpy(), first[0]),
                       "firstStepEos": metrics(eos.numpy(), first[1]),
                       "flowSameInputs": metrics(flow_ref.numpy(), flow_out)}
        latent = np.random.default_rng(1).normal(0, 0.1, (1, 4, 32)).astype(np.float32)
        mimi_capacity = latent.shape[1] * int(model.mimi.encoder_frame_rate / model.mimi.frame_rate)
        decoder_ref = model.mimi.decode_from_latent(
            torch.from_numpy(latent) * lm.emb_std + lm.emb_mean,
            init_states(model.mimi, batch_size=1, sequence_length=mimi_capacity)).numpy().reshape(-1)
        mimi = {f"mimi_{i}": (np.ones if e["key"] == "first" else np.zeros)(e["shape"],
                dtype={"float32": np.float32, "int64": np.int64, "bool": np.bool_}[e["dtype"]])
                for i, e in enumerate(manifest["mimi_states"])}
        decoder_out = sessions["mimi_decoder"].run(None, {"latent": latent, **mimi})[0]
        comparisons["decoderSameLatents"] = metrics(decoder_ref, decoder_out)
        torch.manual_seed(0)
        start = time.monotonic()
        audio = model.generate_audio(voice, text, max_tokens=50).numpy().reshape(-1)
        seconds = time.monotonic() - start
    if (model.sample_rate != 24000 or not np.isfinite(audio).all()
            or not 0 < audio.size <= 480000 or not np.any(audio != 0)):
        raise ValueError("Sortie officielle invalide ou hors borne.")
    wav_path.parent.mkdir(parents=True, exist_ok=True)
    with wav_path.open("xb") as raw:
        with wave.open(raw, "wb") as handle:
            handle.setnchannels(1)
            handle.setsampwidth(2)
            handle.setframerate(24000)
            handle.writeframes((np.clip(audio, -1, 1) * 32767).astype("<i2").tobytes())
    return {"schemaVersion": 1, "trial": "official_pocket_tts_reference_cpu",
            "versions": {name: importlib.metadata.version(name) for name in
                         ("pocket-tts", "torch", "onnxruntime", "numpy", "tokenizers", "safetensors")},
            "officialCodeRevision": lock["officialReference"]["codeRevision"],
            "networkPolicy": "connect_and_name_resolution_blocked",
            "passageId": passage["id"], "startOffsetUtf16": 0,
            "endOffsetUtf16": len(text.encode("utf-16-le")) // 2,
            "preparedTextSha256": hashlib.sha256(prepared.encode()).hexdigest(),
            "candidateRevision": candidate_lock["candidate"]["revision"],
            "scriptSha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            "corpusSha256": hashlib.sha256(corpus_bytes).hexdigest(),
            "textSha256": hashlib.sha256(text.encode()).hexdigest(),
            "tokenIds": ids, "tokenIdsMatchOnnx": True,
            "fp16EmbeddingTableMatchesOfficial": bool(table_matches),
            "fp16VoiceMatchesOfficial": bool(voice_matches),
            "numericalComparisons": comparisons, "numericalAcceptanceThresholds": None,
            "randomSequencesIdenticalAcrossTorchAndNumpy": False,
            "referenceGenerationSeconds": seconds, "samples": int(audio.size),
            "durationSeconds": audio.size / 24000, "sampleRate": 24000,
            "wavSha256": hashlib.sha256(wav_path.read_bytes()).hexdigest(),
            "intelligibility": "not_evaluated", "androidExecuted": False,
            "g0": "not_demonstrated"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--onnx-directory", type=Path, required=True)
    parser.add_argument("--wav", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--passage-id", choices=["fr-01-p1", "fr-04-p1", "fr-05-p1"], default="fr-01-p1")
    parser.add_argument("--audit-lock", type=Path)
    args = parser.parse_args()
    if args.wav.exists() or args.report.exists():
        parser.error("Choisir de nouveaux fichiers pour préserver les preuves précédentes.")
    report = run(args.directory, args.onnx_directory, args.wav, args.passage_id, args.audit_lock)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    with args.report.open("x", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print("Référence officielle générée et comparaisons numériques enregistrées ; G0 non démontré.")

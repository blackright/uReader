"""Provisioning explicite du préflight JNI dans les fichiers privés du prototype debug."""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess

import numpy as np
import onnx
from onnx.reference import ReferenceEvaluator
import onnxruntime as ort


def main(adb):
    root = Path(__file__).resolve().parents[2]
    lock = json.loads((root / "validation/model-lock.json").read_text(encoding="utf-8"))
    directory = root / "validation/private/models/fr-6l"
    spec = importlib.util.spec_from_file_location(
        "verify_files", Path(__file__).with_name("verify-model-files.py"))
    verifier = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(verifier)
    entries = [e for e in lock["downloadFiles"] if e["relativePath"].endswith(".onnx")]
    if {e["relativePath"] for e in entries} != {
            "flow_lm_main_int8.onnx", "flow_lm_flow_int8.onnx", "mimi_decoder_int8.onnx"}:
        raise ValueError("Liste de graphes inattendue.")
    errors = verifier.verify(directory, entries)
    if errors:
        raise ValueError("; ".join(errors))
    structure = json.loads((root / "validation/reports/g0/onnx-structure.json").read_text(encoding="utf-8"))
    options = ort.SessionOptions()
    options.intra_op_num_threads = 1
    options.inter_op_num_threads = 1
    session = ort.InferenceSession(str(directory / "flow_lm_flow_int8.onnx"), options,
                                   providers=["CPUExecutionProvider"])
    inputs = {"c": np.zeros((1, 1024), np.float32), "s": np.zeros((1, 1), np.float32),
              "t": np.ones((1, 1), np.float32),
              "x": np.random.default_rng(0).normal(0, np.sqrt(0.3), (1, 32)).astype(np.float32)}
    host_expected = session.run(None, inputs)[0]
    # Le noyau U8S8 x86 observé sature des sommes intermédiaires INT16.
    # L'oracle indépendant utilise la sémantique ONNX, pas ce résultat matériel.
    reference = ReferenceEvaluator(onnx.load(str(directory / "flow_lm_flow_int8.onnx"), load_external_data=False))
    expected = reference.run(None, inputs)[0]
    if not np.isfinite(expected).all():
        raise ValueError("Sortie hôte invalide.")
    fixture = {k: v.reshape(-1).tolist() for k, v in inputs.items()}
    fixture.update(expected=expected.reshape(-1).tolist(), absoluteTolerance=0.0001)
    fixture["id"] = "zero-conditioning-seed-0"
    fixtures = [fixture]
    for seed, scale in [(1, 0.01), (2, 1.0), (3, 3.0), (4, 0.25)]:
        rng = np.random.default_rng(seed)
        values = {"c": rng.normal(0, scale, (1, 1024)).astype(np.float32),
                  "s": np.zeros((1, 1), np.float32), "t": np.ones((1, 1), np.float32),
                  "x": rng.normal(0, np.sqrt(0.3), (1, 32)).astype(np.float32)}
        output = reference.run(None, values)[0]
        if not np.isfinite(output).all():
            raise ValueError("Sortie de référence non finie.")
        case = {k: v.reshape(-1).tolist() for k, v in values.items()}
        case.update(id=f"conditioning-scale-{scale}-seed-{seed}",
                    expected=output.reshape(-1).tolist(), absoluteTolerance=0.0001)
        fixtures.append(case)
    graphs = []
    for entry in entries:
        graph = next(g for g in structure["graphs"] if g["file"] == entry["relativePath"])
        if graph["sha256"] != entry["sha256"]:
            raise ValueError("Rapport de structure d'une autre révision.")
        graphs.append({"file": entry["relativePath"], "byteSize": entry["byteSize"],
                       "sha256": entry["sha256"], "inputCount": len(graph["inputs"]),
                       "outputCount": len(graph["outputs"])})
    manifest = {"schemaVersion": 1, "purpose": "JNI preflight only; no speech or G0",
                "hostRuntime": ort.__version__, "graphs": graphs, "flowFixture": fixture,
                "flowFixtures": fixtures, "referenceBackend": "onnx.reference.ReferenceEvaluator",
                "referenceVersion": onnx.__version__,
                "originalHostOrtDifference": float(np.abs(host_expected - expected).max())}
    local = root / "validation/private/android-runtime/probe-manifest.json"
    local.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    command = [str(adb), "-d"]
    subprocess.run(command + ["shell", "run-as", "com.ureader.prototype", "mkdir", "-p",
                             "files/ureader-g0-probe"], check=True, timeout=15)
    for source in [*(directory / e["relativePath"] for e in entries), local]:
        # Noms issus de la liste fixe ci-dessus ; aucun chemin de livre ou stockage partagé.
        remote = "run-as com.ureader.prototype sh -c 'cat > files/ureader-g0-probe/" + source.name + "'"
        with source.open("rb") as handle:
            # exec-in conserve notamment 0x1A sous Windows, contrairement au mode shell.
            subprocess.run(command + ["exec-in", remote], stdin=handle, check=True, timeout=90)
        checksum = subprocess.check_output(command + ["shell", "run-as", "com.ureader.prototype",
                    "sha256sum", "files/ureader-g0-probe/" + source.name], timeout=30).decode().split()[0]
        if checksum != hashlib.sha256(source.read_bytes()).hexdigest():
            raise ValueError("Copie privée non conforme : " + source.name)
        print("Copie privée et SHA-256 confirmés :", source.name, flush=True)
    print("Préflight provisionné explicitement. Aucune voix activée, aucun son généré.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", type=Path, default=Path(os.environ.get("LOCALAPPDATA", ""))
                        / "Android/SDK/platform-tools/adb.exe")
    args = parser.parse_args()
    main(args.adb)

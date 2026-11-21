"""Inspection statique locale des graphes de T015, sans inférence ni réseau."""

import argparse
import importlib.metadata
import importlib.util
import json
from pathlib import Path

import onnx


def verify_files(directory, lock_file=None):
    spec = importlib.util.spec_from_file_location(
        "verify_model_files", Path(__file__).with_name("verify-model-files.py"))
    verifier = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(verifier)
    source = lock_file or (Path(__file__).resolve().parents[1] / "model-lock.json")
    lock = json.loads(Path(source).read_text(encoding="utf-8"))
    errors = verifier.verify(directory, lock["downloadFiles"])
    if errors:
        raise ValueError("Fichiers locaux non conformes : " + "; ".join(errors))
    return lock


def describe(value):
    tensor = value.type.tensor_type
    return {
        "name": value.name,
        "type": onnx.TensorProto.DataType.Name(tensor.elem_type),
        "shape": [d.dim_param if d.HasField("dim_param") else d.dim_value
                  for d in tensor.shape.dim],
    }


def inspect(directory, lock_file=None):
    lock = verify_files(directory, lock_file)
    graphs = []
    for entry in lock["downloadFiles"]:
        if not entry["relativePath"].endswith(".onnx"):
            continue
        model = onnx.load(str(directory / entry["relativePath"]), load_external_data=False)
        if (any(t.data_location == onnx.TensorProto.EXTERNAL
                for t in model.graph.initializer)
                or any(n.domain not in ("", "ai.onnx") for n in model.graph.node)
                or model.functions):
            raise ValueError("Graphes externes, fonctions locales ou domaines personnalisés refusés.")
        onnx.checker.check_model(model)
        graphs.append({
            "file": entry["relativePath"], "sha256": entry["sha256"],
            "irVersion": model.ir_version,
            "opsets": [{"domain": o.domain, "version": o.version}
                       for o in model.opset_import],
            "inputs": [describe(v) for v in model.graph.input],
            "outputs": [describe(v) for v in model.graph.output],
            "operators": sorted({n.op_type for n in model.graph.node}),
            "structuralCheck": "passed",
        })
    if len(graphs) != 3:
        raise ValueError("Trois graphes attendus.")
    return {"schemaVersion": 1, "candidateRevision": lock["candidate"]["revision"],
            "onnxVersion": importlib.metadata.version("onnx"),
            "staticInspection": "passed", "graphs": graphs,
            "inferenceExecuted": False, "androidCompatibility": "not_tested"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--lock-file", type=Path, help="Explicit lab audit lock; not a product trust manifest")
    args = parser.parse_args()
    report = inspect(args.directory, args.lock_file)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    with args.report.open("x", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print("Trois graphes vérifiés structurellement ; aucune preuve Android.")

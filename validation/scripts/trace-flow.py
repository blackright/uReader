"""Localise les divergences par tenseur ; modèles dérivés réservés au diagnostic privé."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import numpy as np
import onnx
import onnxruntime as ort


def prepare(directory):
    root = Path(__file__).resolve().parents[2]
    lock = json.loads((root / "validation/model-lock.json").read_text(encoding="utf-8"))
    source = root / "validation/private/models/fr-6l/flow_lm_flow_int8.onnx"
    expected = next(f for f in lock["downloadFiles"] if f["relativePath"] == source.name)
    if hashlib.sha256(source.read_bytes()).hexdigest() != expected["sha256"]:
        raise ValueError("Le graphe source n'est pas conforme.")
    model = onnx.shape_inference.infer_shapes(onnx.load(str(source), load_external_data=False))
    values = {v.name: v for v in [*model.graph.value_info, *model.graph.output, *model.graph.input]}
    names, descriptors = [], []
    for index, node in enumerate(model.graph.node):
        for name in node.output:
            if not name:
                continue
            if name not in values:
                raise ValueError("Type de sortie non inféré : " + name)
            names.append(name)
            descriptors.append({"nodeIndex": index, "operator": node.op_type, "nodeName": node.name,
                                "outputName": name, "inputs": list(node.input)})
    del model.graph.output[:]
    model.graph.output.extend(values[name] for name in names)
    onnx.checker.check_model(model)
    directory.mkdir(parents=True, exist_ok=False)
    path = directory / "flow-trace-01.onnx"
    onnx.save(model, str(path))
    fixture = json.loads((root / "validation/private/android-runtime/probe-manifest.json")
                         .read_text(encoding="utf-8"))["flowFixture"]
    options = ort.SessionOptions()
    options.intra_op_num_threads = 1
    options.inter_op_num_threads = 1
    options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_DISABLE_ALL
    session = ort.InferenceSession(str(path), options, providers=["CPUExecutionProvider"])
    inputs = {k: np.array(fixture[k], np.float32).reshape(1, -1) for k in ["c", "s", "t", "x"]}
    outputs = session.run(None, inputs)
    final = outputs[names.index("flow_dir")].reshape(-1)
    baseline = ort.InferenceSession(str(source), options, providers=["CPUExecutionProvider"]).run(None, inputs)[0].reshape(-1)
    if not np.array_equal(final, baseline):
        raise ValueError("L'instrumentation modifie la sortie hôte ; diagnostic non comparable.")
    with zipfile.ZipFile(directory / "host.zip", "x", compression=zipfile.ZIP_DEFLATED) as archive:
        for index, (value, descriptor) in enumerate(zip(outputs, descriptors)):
            descriptor.update(file=f"{index:04d}.bin", dtype=value.dtype.str, shape=list(value.shape))
            archive.writestr(descriptor["file"], value.tobytes())
        archive.writestr("index.json", json.dumps(descriptors))
    manifest = {"schemaVersion": 1, "sourceSha256": expected["sha256"],
                "traceSha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "outputs": len(outputs), "fixture": fixture, "optimization": "NO_OPT",
                "hostOutputUnchanged": True}
    (directory / "flow-trace-01-manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Trace préparée : {len(outputs)} sorties ; sortie finale hôte strictement inchangée.")


def compare(directory, device_zip, report_path):
    comparisons = []
    with zipfile.ZipFile(directory / "host.zip") as host, zipfile.ZipFile(device_zip) as device:
        descriptions = json.loads(host.read("index.json"))
        actual = json.loads(device.read("index.json"))
        if len(actual) != len(descriptions):
            raise ValueError("Nombre de sorties différent.")
        for descriptor, observed in zip(descriptions, actual):
            if observed["outputName"] != descriptor["outputName"] or observed["shape"] != descriptor["shape"]:
                raise ValueError("Ordre ou forme de sortie différent.")
            dtype = np.dtype(descriptor["dtype"])
            a = np.frombuffer(host.read(descriptor["file"]), dtype=dtype)
            b = np.frombuffer(device.read(observed["file"]), dtype=dtype)
            if a.shape != b.shape:
                raise ValueError("Taille de sortie différente.")
            floating = np.issubdtype(dtype, np.floating)
            delta = np.abs(a.astype(np.float64) - b.astype(np.float64))
            comparisons.append({**descriptor, "equal": bool(np.array_equal(a, b)),
                                "maxAbsoluteError": float(delta.max()) if delta.size else 0,
                                "differentElements": int(np.count_nonzero(a != b)),
                                "floating": bool(floating)})
    def first(predicate):
        return next((c for c in comparisons if predicate(c)), None)
    report = {"schemaVersion": 1, "outputsCompared": len(comparisons),
              "firstMismatch": first(lambda c: not c["equal"]),
              "firstIntegerMismatch": first(lambda c: not c["floating"] and not c["equal"]),
              "firstFloatOver1eMinus4": first(lambda c: c["floating"] and c["maxAbsoluteError"] > 0.0001),
              "finalOutput": first(lambda c: c["outputName"] == "flow_dir"),
              "allOutputs": comparisons, "g0": "not_demonstrated"}
    with report_path.open("x", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(json.dumps({k: v for k, v in report.items() if k != "allOutputs"}, indent=2))


def explain_integer(directory, device_zip, comparison_path, report_path):
    root = Path(__file__).resolve().parents[2]
    source = root / "validation/private/models/fr-6l/flow_lm_flow_int8.onnx"
    manifest = json.loads((directory / "flow-trace-01-manifest.json").read_text(encoding="utf-8"))
    if hashlib.sha256(source.read_bytes()).hexdigest() != manifest["sourceSha256"]:
        raise ValueError("Source différente de celle tracée.")
    comparison = json.loads(comparison_path.read_text(encoding="utf-8"))
    first = comparison["firstIntegerMismatch"]
    model = onnx.load(str(source), load_external_data=False)
    node = next(n for n in model.graph.node if first["outputName"] in n.output)
    if node.op_type != "MatMulInteger" or len(node.input) != 4:
        raise ValueError("Ce diagnostic porte sur MatMulInteger avec ses deux zero-points.")
    constants = {t.name: onnx.numpy_helper.to_array(t) for t in model.graph.initializer}
    with zipfile.ZipFile(directory / "host.zip") as host, zipfile.ZipFile(device_zip) as device:
        descriptions = {e["outputName"]: e for e in json.loads(host.read("index.json"))}

        def read(name, archive):
            if name in constants:
                return constants[name]
            entry = descriptions[name]
            return np.frombuffer(archive.read(entry["file"]), dtype=entry["dtype"]).reshape(entry["shape"])

        a = read(node.input[0], host).astype(np.int64)
        b = read(node.input[1], host).astype(np.int64)
        az = read(node.input[2], host).astype(np.int64)
        bz = read(node.input[3], host).astype(np.int64)
        if (not np.array_equal(a, read(node.input[0], device))
                or not np.array_equal(az, read(node.input[2], device))):
            raise ValueError("Entrées entières différentes ; comparaison de noyaux non isolée.")
        exact = (a - az) @ (b - bz)
        host_result = read(first["outputName"], host).astype(np.int64)
        device_result = read(first["outputName"], device).astype(np.int64)
        products = a[:, :, None] * b[None, :, :]
        pairs = products.reshape(a.shape[0], a.shape[1] // 2, 2, b.shape[1]).sum(axis=2)
        saturated = (pairs.clip(-32768, 32767).sum(axis=1) - az * b.sum(axis=0)
                     - a.sum(axis=1, keepdims=True) * bz + a.shape[1] * az * bz)
        columns = np.flatnonzero((host_result != device_result)[0])
        report = {"operator": node.name, "quantizedInputsIdentical": True,
                  "inputZeroPointsIdentical": True,
                  "hostDiffersFromExactElements": int(np.count_nonzero(host_result != exact)),
                  "androidDiffersFromExactElements": int(np.count_nonzero(device_result != exact)),
                  "hostMatchesSaturatedPairArithmetic": bool(np.array_equal(host_result, saturated)),
                  "androidMatchesExactInt64Arithmetic": bool(np.array_equal(device_result, exact)),
                  "differentColumns": columns.tolist(),
                  "values": [{"column": int(c), "exact": int(exact[0, c]),
                              "host": int(host_result[0, c]), "android": int(device_result[0, c]),
                              "saturatedPairPrediction": int(saturated[0, c])} for c in columns]}
    with report_path.open("x", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)
        handle.write("\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    prepare_parser = sub.add_parser("prepare")
    prepare_parser.add_argument("--directory", type=Path, required=True)
    compare_parser = sub.add_parser("compare")
    compare_parser.add_argument("--directory", type=Path, required=True)
    compare_parser.add_argument("--device-zip", type=Path, required=True)
    compare_parser.add_argument("--report", type=Path, required=True)
    explain_parser = sub.add_parser("explain-integer")
    explain_parser.add_argument("--directory", type=Path, required=True)
    explain_parser.add_argument("--device-zip", type=Path, required=True)
    explain_parser.add_argument("--comparison", type=Path, required=True)
    explain_parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if args.action == "prepare":
        prepare(args.directory)
    elif args.action == "compare":
        compare(args.directory, args.device_zip, args.report)
    else:
        explain_integer(args.directory, args.device_zip, args.comparison, args.report)

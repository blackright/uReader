"""Contrôle local des fichiers de T015 ; aucun réseau, chargement ou activation."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sys


def verify(directory, entries):
    directory = Path(directory).absolute()
    if not isinstance(entries, list) or not entries:
        raise ValueError("Liste de fichiers attendus invalide.")
    names = set()
    for entry in entries:
        name = entry.get("relativePath")
        if (not isinstance(name, str) or not name
                or not re.fullmatch(r"[A-Za-z0-9_./-]+", name)
                or any(part in ("", ".", "..") for part in name.split("/"))
                or PurePosixPath(name).is_absolute() or name in names
                or type(entry.get("byteSize")) is not int
                or entry["byteSize"] < 0
                or not re.fullmatch(r"[a-f0-9]{64}", str(entry.get("sha256", "")))):
            raise ValueError("Métadonnées de vérification invalides.")
        names.add(name)
    if not directory.is_dir():
        return ["Dossier de modèles absent."]
    if any(p.is_symlink() for p in (directory, *directory.parents)):
        return ["Dossier lié symboliquement refusé."]
    errors = []
    for entry in entries:
        name = entry["relativePath"]
        path = directory
        linked = False
        for component in name.split("/"):
            path = path / component
            linked = linked or path.is_symlink()
        if linked:
            errors.append(f"{name} : lien symbolique refusé.")
            continue
        if not path.is_file():
            errors.append(f"{name} : fichier absent.")
            continue
        expected = entry["byteSize"]
        if path.stat().st_size != expected:
            errors.append(f"{name} : taille incorrecte (attendu : {expected} octets).")
            continue
        digest = hashlib.sha256()
        read = 0
        with path.open("rb") as handle:
            while chunk := handle.read(1024 * 1024):
                read += len(chunk)
                if read > expected:
                    break
                digest.update(chunk)
        if read != expected or digest.hexdigest() != entry["sha256"]:
            errors.append(f"{name} : empreinte SHA-256 incorrecte.")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", required=True, type=Path)
    parser.add_argument("--group", choices=("onnx", "reference", "android-runtime"), default="onnx")
    args = parser.parse_args()
    try:
        lock = json.loads((Path(__file__).resolve().parents[1] / "model-lock.json")
                          .read_text(encoding="utf-8"))
        if lock.get("schemaVersion") != 1:
            raise ValueError("Version du document d'audit non prise en charge.")
        if args.group == "onnx":
            entries = lock["downloadFiles"]
        elif args.group == "reference":
            entries = lock["officialReference"]["downloadFiles"]
        else:
            entries = [{"relativePath": f["name"], "byteSize": f["byteSize"],
                        "sha256": f["localSha256"]} for f in lock["androidRuntimeCandidate"]["files"]]
        errors = verify(args.directory, entries)
        for error in errors:
            print(error)
        if errors:
            print("Vérification incomplète. Aucun modèle activé.")
            return 1
        print(f"Intégrité des {len(entries)} fichiers confirmée. "
              "Compatibilité Android et G0 restent à vérifier. Aucune activation.")
        return 0
    except (OSError, ValueError, KeyError, TypeError):
        print("Vérification impossible : accès aux fichiers ou document d'audit invalide.")
        return 1


if __name__ == "__main__":
    sys.exit(main())

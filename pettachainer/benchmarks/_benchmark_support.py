from __future__ import annotations

import importlib
import json
import sys
from pathlib import Path
from typing import Any


def load_chainer(repository: Path, error_type: type[Exception]) -> Any:
    package_root = repository.resolve()
    if not (package_root / "pettachainer" / "pettachainer.py").is_file():
        raise error_type(f"not a PeTTaChainer repository: {package_root}")
    sys.path.insert(0, str(package_root))
    try:
        module = importlib.import_module("pettachainer.pettachainer")
    finally:
        sys.path.pop(0)
    module_path = Path(module.__file__).resolve()
    if package_root not in module_path.parents:
        raise error_type(
            f"loaded PeTTaChainer from {module_path}, not {package_root}"
        )
    return module.PeTTaChainer


def write_json(path: Path, payload: Any) -> None:
    path.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

"""CLI contract: one decision token, or an error code with exit status 2."""

import json
import subprocess
import sys
from pathlib import Path

import pytest

from gate_check_independent.cli import main
from gate_check_independent.types import DEFAULT_RESAMPLES, DEFAULT_SEED

ROOT = Path(__file__).resolve().parents[1]
EXAMPLES = ROOT / "examples"


@pytest.mark.parametrize(
    ("name", "expected"),
    [
        ("exactly_5_percent_false_accept.json", "APPLE"),
        ("exactly_5pp.json", "SARVAM"),
        ("sarvam_only.json", "SARVAM"),
        ("child_false_accept_cap.json", "NO_GO"),
    ],
)
def test_examples_print_the_decision(name: str, expected: str, capsys: pytest.CaptureFixture[str]) -> None:
    assert main([str(EXAMPLES / name)]) == 0
    captured = capsys.readouterr()
    assert captured.out == f"{expected}\n"
    assert captured.err == f"seed={DEFAULT_SEED}\n"


def test_exactly_090_is_invalid_because_false_accept_denominator_is_zero(
    capsys: pytest.CaptureFixture[str],
) -> None:
    assert main([str(EXAMPLES / "exactly_090.json")]) == 2
    captured = capsys.readouterr()
    assert captured.out == "INVALID_STUDY\n"
    assert "false-accept" in captured.err


def test_missing_age_example_exits_out_of_cohort(capsys: pytest.CaptureFixture[str]) -> None:
    assert main([str(EXAMPLES / "missing_age.json")]) == 2
    captured = capsys.readouterr()
    assert captured.out == "OUT_OF_COHORT\n"
    assert "c2" in captured.err


def test_json_report_uses_exact_ratios_and_logs_the_seed(capsys: pytest.CaptureFixture[str]) -> None:
    assert main([str(EXAMPLES / "exactly_5_percent_false_accept.json"), "--format", "json"]) == 0
    report = json.loads(capsys.readouterr().out)
    assert report["decision"] == "APPLE"
    assert report["seed"] == DEFAULT_SEED
    assert report["warnings"] == []
    assert report["apple"]["agreement"] == {"numerator": 99, "denominator": 100}
    assert report["apple"]["false_accept_rate"] == {
        "status": "ratio",
        "numerator": 1,
        "denominator": 20,
    }
    assert report["apple"]["false_reject_rate"] == {
        "status": "ratio",
        "numerator": 0,
        "denominator": 1,
    }
    assert report["agreement_delta"] == {"numerator": 0, "denominator": 1}
    assert report["interval"]["seed"] == DEFAULT_SEED
    assert report["interval"]["resamples"] == DEFAULT_RESAMPLES
    assert report["interval"]["method"].startswith("paired child-cluster bootstrap")
    assert report["interval"]["low"] == {"numerator": 0, "denominator": 1}
    assert report["clearly_beats"]["sarvam_wins"] is False


def test_repeated_runs_match(capsys: pytest.CaptureFixture[str]) -> None:
    path = str(EXAMPLES / "exactly_5pp.json")
    assert main([path, "--format", "json", "--seed", "11", "--resamples", "40"]) == 0
    first = capsys.readouterr().out
    assert main([path, "--format", "json", "--seed", "11", "--resamples", "40"]) == 0
    assert capsys.readouterr().out == first


def test_bad_confidence_and_bad_json(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    sample = EXAMPLES / "exactly_090.json"
    assert main([str(sample), "--confidence", "nope"]) == 2
    assert capsys.readouterr().out == "INVALID_INPUT\n"
    broken = tmp_path / "broken.json"
    broken.write_text("{", encoding="utf-8")
    assert main([str(broken), "--format", "json"]) == 2
    body = json.loads(capsys.readouterr().out)
    assert body["error"] == "INVALID_INPUT"


def test_module_entrypoint_prints_sarvam() -> None:
    completed = subprocess.run(
        [sys.executable, "-m", "gate_check_independent", str(EXAMPLES / "sarvam_only.json")],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    assert completed.returncode == 0
    assert completed.stdout == "SARVAM\n"
    assert completed.stderr == f"seed={DEFAULT_SEED}\n"


def test_no_go_exits_zero() -> None:
    completed = subprocess.run(
        [
            sys.executable,
            "-m",
            "gate_check_independent",
            str(EXAMPLES / "child_false_accept_cap.json"),
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    assert completed.returncode == 0
    assert completed.stdout == "NO_GO\n"
    assert completed.stderr == f"seed={DEFAULT_SEED}\n"

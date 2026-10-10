"""Command line for the independent M0 gate check.

Text mode prints one token: APPLE, SARVAM, NO_GO, or an error code.
NO_GO is a completed decision and exits 0. Cohort and schema errors exit 2.
"""

from __future__ import annotations

import argparse
import json
import sys
from fractions import Fraction
from pathlib import Path

from gate_check_independent.errors import GateCheckError
from gate_check_independent.gate import decision_to_dict, evaluate
from gate_check_independent.types import DEFAULT_CONFIDENCE, DEFAULT_RESAMPLES, DEFAULT_SEED


def console_main() -> None:
    raise SystemExit(main())


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gate-check-independent",
        description=(
            "Decide APPLE, SARVAM, or NO_GO from a JSON results file. "
            "The file schema is documented in tools/gate_check_independent/README.md."
        ),
    )
    parser.add_argument("results", type=Path, help="path to the JSON results file")
    parser.add_argument(
        "--seed",
        type=int,
        default=DEFAULT_SEED,
        help=f"integer seed for random.Random (default {DEFAULT_SEED})",
    )
    parser.add_argument(
        "--resamples",
        type=int,
        default=DEFAULT_RESAMPLES,
        help=f"bootstrap resamples (default {DEFAULT_RESAMPLES})",
    )
    parser.add_argument(
        "--confidence",
        default=f"{DEFAULT_CONFIDENCE.numerator}/{DEFAULT_CONFIDENCE.denominator}",
        help=(
            "two-sided confidence level as a fraction or decimal "
            f"(default {DEFAULT_CONFIDENCE.numerator}/{DEFAULT_CONFIDENCE.denominator})"
        ),
    )
    parser.add_argument(
        "--format",
        choices=("text", "json"),
        default="text",
        help="text prints the decision token; json prints the full report",
    )
    args = parser.parse_args(argv)
    try:
        try:
            confidence = Fraction(str(args.confidence))
        except ValueError as exc:
            raise GateCheckError("INVALID_INPUT", f"confidence must be a fraction, not {args.confidence!r}") from exc
        payload = json.loads(args.results.read_text(encoding="utf-8"))
        result = evaluate(
            payload,
            seed=args.seed,
            resamples=args.resamples,
            confidence=confidence,
        )
    except GateCheckError as exc:
        _emit_error(args.format, exc)
        return 2
    except json.JSONDecodeError as exc:
        _emit_error(args.format, GateCheckError("INVALID_INPUT", f"results file is not JSON: {exc.msg}"))
        return 2
    except OSError as exc:
        _emit_error(args.format, GateCheckError("INVALID_INPUT", str(exc)))
        return 2
    if args.format == "json":
        json.dump(decision_to_dict(result), sys.stdout, indent=2)
        sys.stdout.write("\n")
    else:
        print(result.decision)
    print(f"seed={result.interval.seed}", file=sys.stderr)
    for warning in result.warnings:
        print(f"warning: {warning}", file=sys.stderr)
    return 0


def _emit_error(fmt: str, exc: GateCheckError) -> None:
    if fmt == "json":
        json.dump({"error": exc.code, "message": exc.message}, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return
    print(exc.code)
    print(exc.message, file=sys.stderr)

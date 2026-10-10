"""Independent M0 speech-engine GO/NO-GO gate.

This package is a clean-room reading of the M0 decision rules. It does not
import or reproduce another harness.
"""

from gate_check_independent.errors import GateCheckError
from gate_check_independent.gate import GateDecision, evaluate
from gate_check_independent.types import DEFAULT_CONFIDENCE, DEFAULT_RESAMPLES, DEFAULT_SEED

__all__ = [
    "DEFAULT_CONFIDENCE",
    "DEFAULT_RESAMPLES",
    "DEFAULT_SEED",
    "GateCheckError",
    "GateDecision",
    "evaluate",
]

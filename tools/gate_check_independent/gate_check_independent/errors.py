"""Errors raised by the independent M0 gate check."""


class GateCheckError(Exception):
    """A results file cannot be turned into APPLE, SARVAM, or NO_GO.

    ``code`` is a stable token printed by the CLI. ``OUT_OF_COHORT`` means a
    child is missing an age or class, or is outside ages 6–8 or classes 1–3.
    ``INVALID_STUDY`` means a pooled false-accept or false-reject denominator
    is 0, so the study cannot pass. ``UNPAIRED_RECORDING`` means a recording
    has no word judged by both engines. ``INVALID_INPUT`` means the file (or a
    CLI setting) does not match the schema. ``INSUFFICIENT_DATA`` means a
    rate was asked of an empty word list.
    """

    def __init__(self, code: str, message: str) -> None:
        super().__init__(f"{code}: {message}")
        self.code = code
        self.message = message

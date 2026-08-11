from __future__ import annotations

UZBEK_PHONE_FORMAT = "+998 XX XXX XXXX"
UZBEK_PHONE_VALIDATION_MESSAGE = f"Use Uzbekistan phone format: {UZBEK_PHONE_FORMAT}."


class UzbekPhoneNumberError(ValueError):
    pass


def normalize_uzbek_phone_number(value: str) -> str:
    trimmed = value.strip()
    if not trimmed:
        return ""

    if any(character.isalpha() for character in trimmed):
        raise UzbekPhoneNumberError(UZBEK_PHONE_VALIDATION_MESSAGE)

    digits = "".join(character for character in trimmed if character.isdigit())
    if not trimmed.startswith("+") or not digits.startswith("998") or len(digits) != 12:
        raise UzbekPhoneNumberError(UZBEK_PHONE_VALIDATION_MESSAGE)

    operator_code = digits[3:5]
    first_part = digits[5:8]
    second_part = digits[8:12]
    return f"+998 {operator_code} {first_part} {second_part}"

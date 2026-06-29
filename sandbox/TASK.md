# Task: upgrade the calculator

`calc.py` currently evaluates expressions strictly left to right, so `2 + 3 * 4`
returns 20 instead of 14.

Please:

1. Fix operator precedence (`*` and `/` before `+` and `-`).
2. Add support for parentheses and exponentiation (`^` or `**`).
3. Handle errors gracefully (division by zero, malformed input) with clear messages.
4. Add a pytest test file covering all of the above, and make sure it passes.

Keep it dependency-free where reasonable.

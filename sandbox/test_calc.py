"""Tests for the calculator in calc.py.

Run with: pytest sandbox/test_calc.py
"""
import math
import subprocess
import sys
from pathlib import Path

import pytest

from calc import CalcError, calc, tokenize

CALC_PY = Path(__file__).with_name("calc.py")


# --------------------------------------------------------------------------- #
# Basic arithmetic
# --------------------------------------------------------------------------- #
@pytest.mark.parametrize(
    "expr, expected",
    [
        ("1 + 1", 2),
        ("10 - 4", 6),
        ("6 * 7", 42),
        ("8 / 2", 4),
        ("0", 0),
        ("42", 42),
        ("3.5 + 1.5", 5),
        (".5 + .5", 1),
        ("2.", 2),
        ("1e3", 1000),
        ("2.5E-1", 0.25),
    ],
)
def test_basic(expr, expected):
    assert calc(expr) == pytest.approx(expected)


def test_whitespace_is_insignificant():
    assert calc("  2   +\t3 *\n4 ") == calc("2+3*4")


# --------------------------------------------------------------------------- #
# Precedence
# --------------------------------------------------------------------------- #
@pytest.mark.parametrize(
    "expr, expected",
    [
        ("2 + 3 * 4", 14),          # the original bug: not 20
        ("2 * 3 + 4", 10),
        ("20 - 2 * 5", 10),
        ("1 + 2 - 3 + 4", 4),       # left associative + / -
        ("100 / 10 / 2", 5),        # left associative /
        ("2 - 3 - 4", -5),
        ("10 - 2 + 3", 11),
        ("6 / 2 * 3", 9),           # * and / share precedence, left to right
    ],
)
def test_precedence(expr, expected):
    assert calc(expr) == pytest.approx(expected)


# --------------------------------------------------------------------------- #
# Parentheses
# --------------------------------------------------------------------------- #
@pytest.mark.parametrize(
    "expr, expected",
    [
        ("(2 + 3) * 4", 20),
        ("2 * (3 + 4)", 14),
        ("((1 + 2))", 3),
        ("(2 + 3) * (4 - 1)", 15),
        ("2 * (3 + (4 * 5))", 46),
        ("-(3 + 4)", -7),
        ("(((((5)))))", 5),
        ("10 / (2 + 3)", 2),
    ],
)
def test_parentheses(expr, expected):
    assert calc(expr) == pytest.approx(expected)


# --------------------------------------------------------------------------- #
# Exponentiation
# --------------------------------------------------------------------------- #
@pytest.mark.parametrize(
    "expr, expected",
    [
        ("2 ^ 3", 8),
        ("2 ** 3", 8),
        ("2 ^ 10", 1024),
        ("9 ^ 0.5", 3),
        ("4 ** 0.5", 2),
        ("2 ^ -2", 0.25),           # unary minus in the exponent
        ("2 ** -2", 0.25),
        ("2 ^ 3 ^ 2", 512),         # right associative: 2 ^ (3 ^ 2)
        ("2 ** 3 ** 2", 512),
        ("(2 ^ 3) ^ 2", 64),        # explicit grouping overrides associativity
        ("-2 ^ 2", -4),             # exponent binds tighter than unary minus
        ("-2 ** 2", -4),
        ("2 ^ 3 * 2", 16),          # exponent binds tighter than *
        ("2 * 3 ^ 2", 18),
        ("2 + 3 ^ 2", 11),
        ("2 ^ 2 ^ 2 ^ 2", 65536),   # 2 ^ (2 ^ (2 ^ 2))
    ],
)
def test_exponentiation(expr, expected):
    assert calc(expr) == pytest.approx(expected)


def test_caret_and_double_star_equivalent():
    for base_expr in ["2 ^ 3 ^ 2", "-2 ^ 2", "2 ^ -2", "(1+1) ^ 3"]:
        star_expr = base_expr.replace("^", "**")
        assert calc(base_expr) == pytest.approx(calc(star_expr))


# --------------------------------------------------------------------------- #
# Unary operators
# --------------------------------------------------------------------------- #
@pytest.mark.parametrize(
    "expr, expected",
    [
        ("-5", -5),
        ("+5", 5),
        ("--5", 5),
        ("---5", -5),
        ("-+-5", 5),
        ("3 - -2", 5),
        ("3 + -2", 1),
        ("-3 * -3", 9),
        ("2 * -3", -6),
    ],
)
def test_unary(expr, expected):
    assert calc(expr) == pytest.approx(expected)


# --------------------------------------------------------------------------- #
# Division by zero
# --------------------------------------------------------------------------- #
@pytest.mark.parametrize("expr", ["1 / 0", "1 / (2 - 2)", "5 / 0.0", "10 / (3 - 3) + 1"])
def test_division_by_zero(expr):
    with pytest.raises(CalcError, match="division by zero"):
        calc(expr)


def test_calc_error_is_value_error():
    assert issubclass(CalcError, ValueError)
    with pytest.raises(ValueError):
        calc("1 / 0")


# --------------------------------------------------------------------------- #
# Malformed input
# --------------------------------------------------------------------------- #
@pytest.mark.parametrize(
    "expr",
    [
        "",                 # empty
        "   ",              # whitespace only
        "2 +",              # dangling operator
        "+",                # operator with no operands
        "* 3",              # leading binary operator
        "2 3",              # two numbers, no operator
        "2 + 3 4",          # trailing number
        "(2 + 3",           # unbalanced open paren
        "2 + 3)",           # unbalanced close paren
        "()",               # empty parens
        "2 @ 3",            # unknown character
        "2 ^",              # dangling exponent
        "/ 2",              # leading binary operator
        "3 *",              # dangling multiply
        "2..3",             # malformed number
        "2 + (3 * )",       # operator before close paren
        "5 6 +",            # garbage ordering
    ],
)
def test_malformed_input_raises(expr):
    with pytest.raises(CalcError):
        calc(expr)


def test_error_messages_are_clear():
    with pytest.raises(CalcError, match="empty expression"):
        calc("")
    with pytest.raises(CalcError, match="unexpected character"):
        calc("2 @ 3")
    with pytest.raises(CalcError, match="closing parenthesis"):
        calc("(1 + 2")
    with pytest.raises(CalcError, match="unexpected end of expression"):
        calc("2 +")
    with pytest.raises(CalcError, match="malformed number"):
        calc("1e+")  # exponent marker with no digits


def test_non_string_input():
    with pytest.raises(CalcError, match="must be a string"):
        calc(42)  # type: ignore[arg-type]


# --------------------------------------------------------------------------- #
# Tokenizer details
# --------------------------------------------------------------------------- #
def test_double_star_tokenizes_as_caret():
    assert tokenize("2 ** 3") == [("NUMBER", 2.0), ("OP", "^"), ("NUMBER", 3.0)]


def test_negative_base_fractional_power_rejected():
    # (-1) ** 0.5 is complex in Python; we reject rather than return a complex.
    with pytest.raises(CalcError, match="not a real number"):
        calc("(-1) ^ 0.5")


# --------------------------------------------------------------------------- #
# Tricky / edge cases
# --------------------------------------------------------------------------- #
@pytest.mark.parametrize(
    "expr, expected",
    [
        ("0 ^ 0", 1),               # Python convention
        ("1000000 * 1000000", 1e12),
        ("2 ^ 0", 1),
        ("0 ^ 5", 0),
        ("-(2 ^ 2) + 2 ^ 2", 0),
        ("3 + 4 * 2 / (1 - 5) ^ 2", 3.5),  # a classic mixed expression
    ],
)
def test_edge_cases(expr, expected):
    assert calc(expr) == pytest.approx(expected)


def test_result_matches_python_semantics():
    # Sanity-check a handful of expressions against Python's own evaluator
    # (using ^ -> ** substitution), since we deliberately mirror its rules.
    for expr in ["2 + 3 * 4", "-2 ** 2", "2 ** 3 ** 2", "(2 + 3) * 4", "10 / 4"]:
        assert calc(expr) == pytest.approx(eval(expr.replace("^", "**")))


def test_return_type_is_float():
    assert isinstance(calc("2 + 2"), float)


# --------------------------------------------------------------------------- #
# CLI entrypoint
# --------------------------------------------------------------------------- #
def _run_cli(*args):
    return subprocess.run(
        [sys.executable, str(CALC_PY), *args],
        capture_output=True,
        text=True,
    )


def test_cli_success():
    proc = _run_cli("2 + 3 * 4")
    assert proc.returncode == 0
    assert proc.stdout.strip() == "14.0"


def test_cli_division_by_zero():
    proc = _run_cli("1 / 0")
    assert proc.returncode == 1
    assert "division by zero" in proc.stderr


def test_cli_malformed():
    proc = _run_cli("2 +")
    assert proc.returncode == 1
    assert "error:" in proc.stderr


def test_cli_usage_without_args():
    proc = _run_cli()
    assert proc.returncode == 2
    assert "usage:" in proc.stderr

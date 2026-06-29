#!/usr/bin/env python3
"""Tiny arithmetic calculator with a proper expression parser.

Supports:
  * the four basic operators ``+ - * /`` with correct precedence
    (``*`` and ``/`` bind tighter than ``+`` and ``-``);
  * parentheses for grouping;
  * exponentiation via either ``^`` or ``**`` (the two are exact synonyms);
  * unary plus and minus.

Design choices worth documenting
--------------------------------
* Exponentiation is *right associative*: ``2 ^ 3 ^ 2`` == ``2 ^ (3 ^ 2)`` == 512,
  matching standard mathematical and Python (``**``) convention.
* Exponentiation binds *tighter* than unary minus on its left, so ``-2 ^ 2`` == -4
  (parsed as ``-(2 ^ 2)``), again mirroring Python's ``-2 ** 2``.
* The right operand of an exponent may itself be unary, so ``2 ^ -2`` == 0.25.

Grammar (recursive descent)::

    expr   := term  (('+' | '-') term)*
    term   := unary (('*' | '/') unary)*
    unary  := ('+' | '-') unary | power
    power  := atom ('^' unary)?           # right associative
    atom   := NUMBER | '(' expr ')'

The implementation is intentionally dependency-free (standard library only).
"""
from __future__ import annotations

import sys
from typing import List, Tuple, Union

# A token is a (type, value) pair. Value is a float for numbers, else the symbol.
Token = Tuple[str, Union[str, float]]


class CalcError(ValueError):
    """Raised for any problem evaluating an expression (malformed input,
    division by zero, etc.). Subclasses :class:`ValueError` so callers that
    already catch ``ValueError`` keep working."""


# --------------------------------------------------------------------------- #
# Tokenizer
# --------------------------------------------------------------------------- #
def tokenize(expr: str) -> List[Token]:
    """Turn a source string into a list of tokens.

    Raises :class:`CalcError` on unexpected characters or malformed numbers.
    """
    tokens: List[Token] = []
    i = 0
    n = len(expr)
    while i < n:
        ch = expr[i]

        # Whitespace is insignificant.
        if ch.isspace():
            i += 1
            continue

        # Numbers: an integer/decimal, optionally with a decimal point and an
        # exponent (e.g. 1e3, 2.5E-4). We let float() do the final validation
        # so malformed numbers are reported clearly.
        if ch.isdigit() or ch == ".":
            start = i
            seen_dot = False
            seen_exp = False
            while i < n:
                c = expr[i]
                if c.isdigit():
                    i += 1
                elif c == "." and not seen_dot and not seen_exp:
                    seen_dot = True
                    i += 1
                elif c in "eE" and not seen_exp and i > start:
                    seen_exp = True
                    i += 1
                    # optional sign immediately after the exponent marker
                    if i < n and expr[i] in "+-":
                        i += 1
                else:
                    break
            raw = expr[start:i]
            try:
                value = float(raw)
            except ValueError:
                raise CalcError(f"malformed number: {raw!r}")
            tokens.append(("NUMBER", value))
            continue

        # `**` is the two-character synonym for `^`.
        if ch == "*" and i + 1 < n and expr[i + 1] == "*":
            tokens.append(("OP", "^"))
            i += 2
            continue

        if ch in "+-*/^":
            tokens.append(("OP", ch))
            i += 1
            continue

        if ch == "(":
            tokens.append(("LPAREN", ch))
            i += 1
            continue

        if ch == ")":
            tokens.append(("RPAREN", ch))
            i += 1
            continue

        raise CalcError(f"unexpected character: {ch!r}")

    return tokens


# --------------------------------------------------------------------------- #
# Parser / evaluator (recursive descent)
# --------------------------------------------------------------------------- #
class _Parser:
    def __init__(self, tokens: List[Token]) -> None:
        self.tokens = tokens
        self.pos = 0

    def _peek(self) -> Token:
        if self.pos < len(self.tokens):
            return self.tokens[self.pos]
        return ("EOF", "")

    def _advance(self) -> Token:
        tok = self._peek()
        self.pos += 1
        return tok

    def _at_op(self, *symbols: str) -> bool:
        kind, value = self._peek()
        return kind == "OP" and value in symbols

    def parse(self) -> float:
        if not self.tokens:
            raise CalcError("empty expression")
        result = self._expr()
        if self.pos != len(self.tokens):
            value = self._peek()[1]
            raise CalcError(f"unexpected token: {value!r}")
        return result

    # expr := term (('+' | '-') term)*
    def _expr(self) -> float:
        value = self._term()
        while self._at_op("+", "-"):
            op = self._advance()[1]
            rhs = self._term()
            value = value + rhs if op == "+" else value - rhs
        return value

    # term := unary (('*' | '/') unary)*
    def _term(self) -> float:
        value = self._unary()
        while self._at_op("*", "/"):
            op = self._advance()[1]
            rhs = self._unary()
            if op == "*":
                value = value * rhs
            else:
                if rhs == 0:
                    raise CalcError("division by zero")
                value = value / rhs
        return value

    # unary := ('+' | '-') unary | power
    def _unary(self) -> float:
        if self._at_op("+", "-"):
            op = self._advance()[1]
            operand = self._unary()
            return operand if op == "+" else -operand
        return self._power()

    # power := atom ('^' unary)?   (right associative)
    def _power(self) -> float:
        base = self._atom()
        if self._at_op("^"):
            self._advance()
            exponent = self._unary()  # right side may be unary, e.g. 2 ^ -3
            try:
                result = base ** exponent
            except (OverflowError, ValueError) as exc:
                raise CalcError(f"cannot evaluate exponentiation: {exc}")
            # e.g. (-1) ** 0.5 yields a complex number in Python; reject it.
            if isinstance(result, complex):
                raise CalcError("result is not a real number")
            return float(result)
        return base

    # atom := NUMBER | '(' expr ')'
    def _atom(self) -> float:
        kind, value = self._peek()
        if kind == "NUMBER":
            self._advance()
            return float(value)
        if kind == "LPAREN":
            self._advance()
            inner = self._expr()
            if self._peek()[0] != "RPAREN":
                raise CalcError("missing closing parenthesis")
            self._advance()
            return inner
        if kind == "EOF":
            raise CalcError("unexpected end of expression")
        raise CalcError(f"unexpected token: {value!r}")


def calc(expr: str) -> float:
    """Evaluate an arithmetic expression and return the result as a float.

    Raises :class:`CalcError` (a subclass of ``ValueError``) for malformed
    input or division by zero.
    """
    if not isinstance(expr, str):
        raise CalcError("expression must be a string")
    return _Parser(tokenize(expr)).parse()


def main(argv: List[str]) -> int:
    if len(argv) != 2:
        prog = argv[0] if argv else "calc.py"
        print(f"usage: {prog} <expression>", file=sys.stderr)
        print(f'example: {prog} "2 + 3 * 4"', file=sys.stderr)
        return 2
    try:
        print(calc(argv[1]))
    except CalcError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

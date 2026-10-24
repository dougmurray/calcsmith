#!/usr/bin/env python3
"""Port the formula tables from analog_engineer_assistant (Rust) to Swift.

Usage: tools/port_formulas.py <path-to-analog_engineer_assistant> <output-dir>

Parses the Rust struct literals in src/formulas/*.rs and emits one Swift file
per topic into Sources/CalcsmithCore/Formulas/. Compute closures are translated
textually; Swift-side Double extensions (Sources/CalcsmithCore/RustMath.swift)
provide the Rust-style method names (.sqrt(), .ln(), .powi(), ...).
"""
import os
import re
import sys

TOPICS = [
    ("conversions", "Conversions"),
    ("basics", "The Basics"),
    ("amplifiers", "Amplifiers"),
    ("pcb_wire", "PCB and Wire"),
    ("sensor", "Sensor"),
    ("digital", "Digital"),
    ("adc", "ADC"),
    ("dac", "DAC"),
    ("multiplexer", "Multiplexer"),
    ("rf", "RF"),
]


class Parser:
    """Minimal recursive-descent parser for the Rust literal subset used."""

    def __init__(self, text):
        self.s = text
        self.i = 0

    def ws(self):
        while True:
            m = re.compile(r"\s+|//[^\n]*").match(self.s, self.i)
            if not m or m.end() == self.i:
                return
            self.i = m.end()

    def peek(self, tok):
        self.ws()
        return self.s.startswith(tok, self.i)

    def eat(self, tok):
        self.ws()
        if not self.s.startswith(tok, self.i):
            raise SyntaxError(f"expected {tok!r} at {self.s[self.i:self.i+60]!r}")
        self.i += len(tok)

    def ident(self):
        self.ws()
        m = re.compile(r"[A-Za-z_][A-Za-z0-9_]*").match(self.s, self.i)
        if not m:
            raise SyntaxError(f"expected ident at {self.s[self.i:self.i+60]!r}")
        self.i = m.end()
        return m.group(0)

    def string(self):
        self.ws()
        assert self.s[self.i] == '"'
        j = self.i + 1
        out = []
        while self.s[j] != '"':
            if self.s[j] == "\\":
                out.append(self.s[j : j + 2])
                j += 2
            else:
                out.append(self.s[j])
                j += 1
        self.i = j + 1
        return "".join(out)

    def raw_until_delim(self):
        """Capture raw source up to the next ',' or closing bracket at depth 0."""
        self.ws()
        depth = 0
        j = self.i
        while True:
            c = self.s[j]
            if c in "([{":
                depth += 1
            elif c in ")]}":
                if depth == 0:
                    break
                depth -= 1
            elif c == "," and depth == 0:
                break
            j += 1
        raw = self.s[self.i : j].strip()
        self.i = j
        return raw

    def value(self):
        self.ws()
        if self.peek('"'):
            return self.string()
        if self.peek("&["):
            self.eat("&[")
            return self.list_items("]")
        if self.peek("vec!["):
            self.eat("vec![")
            return self.list_items("]")
        if self.peek("None"):
            self.eat("None")
            return None
        if self.peek("Some("):
            self.eat("Some(")
            v = self.value()
            if self.peek(","):
                self.eat(",")
            self.eat(")")
            return v
        if self.peek("|v|"):
            self.eat("|v|")
            return ("closure", self.raw_until_delim())
        m = re.compile(r"[A-Z][A-Za-z]*\s*\{").match(self.s, self.i)
        if m:
            name = self.ident()
            self.eat("{")
            fields = {}
            while not self.peek("}"):
                key = self.ident()
                self.eat(":")
                fields[key] = self.value()
                if self.peek(","):
                    self.eat(",")
            self.eat("}")
            fields["__type"] = name
            return fields
        return ("raw", self.raw_until_delim())

    def list_items(self, close):
        items = []
        while not self.peek(close):
            items.append(self.value())
            if self.peek(","):
                self.eat(",")
        self.eat(close)
        return items


def rust_expr_to_swift(e):
    e = e.replace("std::f64::consts::PI", "Double.pi")
    e = e.replace("std::f64::consts::TAU", "(2.0 * Double.pi)")
    e = re.sub(r"\bPI\b", "Double.pi", e)
    e = re.sub(r"\b(\d+(?:\.\d+)?)f64\b", r"Double(\1)", e)
    e = re.sub(r"(v\[\d+\]) as i32", r"Int(\1)", e)
    e = e.replace(".round()", ".rounded()")
    if " as " in e:
        raise ValueError(f"unhandled cast in {e!r}")
    return e


def closure_to_swift(body, indent):
    body = body.strip()
    if body.startswith("{") and body.endswith("}"):
        inner = body[1:-1].strip()
        # split on top-level semicolons
        stmts, depth, cur = [], 0, []
        for c in inner:
            if c in "([{":
                depth += 1
            elif c in ")]}":
                depth -= 1
            if c == ";" and depth == 0:
                stmts.append("".join(cur).strip())
                cur = []
            else:
                cur.append(c)
        tail = "".join(cur).strip()
        lines = [rust_expr_to_swift(" ".join(s.split())) for s in stmts]
        lines.append("return " + rust_expr_to_swift(" ".join(tail.split())))
        pad = " " * (indent + 4)
        return "{ v in\n" + "\n".join(pad + l for l in lines) + "\n" + " " * indent + "}"
    return "{ v in " + rust_expr_to_swift(" ".join(body.split())) + " }"


def swift_str(s):
    return '"' + s.replace("\\'", "'") + '"'


def num(raw):
    if isinstance(raw, tuple):
        raw = raw[1]
    return rust_expr_to_swift(raw)


def helper_fns(text):
    """Translate free helper functions (e.g. rf.rs l_network_q)."""
    out = []
    for m in re.finditer(r"fn (\w+)\(([^)]*)\) -> f64 \{(.*?)\n\}", text, re.S):
        name, params, body = m.groups()
        if name == "formulas":
            continue
        ps = ", ".join(f"_ {p.split(':')[0].strip()}: Double" for p in params.split(","))
        stmts = [s.strip() for s in body.strip().split(";")]
        lines = [rust_expr_to_swift(s) for s in stmts[:-1]]
        lines.append("return " + rust_expr_to_swift(stmts[-1]))
        out.append(
            f"private func {name}({ps}) -> Double {{\n"
            + "\n".join("    " + l for l in lines)
            + "\n}\n"
        )
    return out


def emit_topic(mod, title, text):
    start = text.index("pub fn formulas()")
    p = Parser(text)
    p.i = text.index("vec![", start)
    entries = p.value()
    func = "".join(w.capitalize() for w in mod.split("_"))
    lines = [
        "// Generated by tools/port_formulas.py from analog_engineer_assistant",
        f"// src/formulas/{mod}.rs — edit freely; regenerate only to re-sync.",
        "",
        "import Foundation",
        "",
    ]
    lines += helper_fns(text)
    lines += [
        "extension FormulaLibrary {",
        f"    static func {func[0].lower() + func[1:]}() -> Topic {{",
        f"        Topic(name: {swift_str(title)}, formulas: [",
    ]
    for f in entries:
        note = f"note: {swift_str(f['note'])}, " if f.get("note") else ""
        lines.append(f"            Formula(name: {swift_str(f['name'])}, {note}variants: [")
        for var in f["variants"]:
            lines.append(
                f"                Variant(solvesFor: {swift_str(var['solves_for'])}, "
                f"expression: {swift_str(var['expression'])}, "
                f"unit: {swift_str(var['output_unit'])},"
            )
            lines.append("                        inputs: [")
            for vd in var["inputs"]:
                lines.append(
                    f"                            Var({swift_str(vd['symbol'])}, "
                    f"{swift_str(vd['name'])}, {swift_str(vd['unit'])}, {num(vd['default'])}),"
                )
            lines.append("                        ]) " + closure_to_swift(var["compute"][1], 24) + ",")
        lines.append("            ]),")
    lines += ["        ])", "    }", "}", ""]
    return func, "\n".join(lines), sum(len(f["variants"]) for f in entries), len(entries)


def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    total_f = total_v = 0
    for mod, title in TOPICS:
        with open(os.path.join(src, "src", "formulas", f"{mod}.rs"), encoding="utf-8") as fh:
            text = fh.read()
        func, swift, nv, nf = emit_topic(mod, title, text)
        total_f += nf
        total_v += nv
        with open(os.path.join(out, f"{func}.swift"), "w", encoding="utf-8") as fh:
            fh.write(swift)
        print(f"{title:14} {nf:3} formulas {nv:3} variants")
    print(f"{'total':14} {total_f:3} formulas {total_v:3} variants")


if __name__ == "__main__":
    main()

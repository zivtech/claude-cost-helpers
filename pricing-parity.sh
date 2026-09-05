#!/bin/bash
# Pricing parity check — every helper embeds its own copy of the price table
# because helpers are self-contained by design (each installs alone). Prices
# change and the cache math improves; this script fails if any copy has drifted
# from the others, so an update is one commit touching every copy, verified.
#
# Checks, per file: the input $/MTok table (same keys, same order — order
# matters for substring matching — same values), the cache-read rule, and the
# presence of both cache-write multipliers (1.25 for 5m, 2.0 for 1h).
#
# Run: ./pricing-parity.sh   (exit 0 = all copies identical)

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 - "$HERE" <<'PY'
import ast, os, re, sys
root = sys.argv[1]
FILES = [
    "idle-tax/cache-idle-timer.sh",
    "delegation-cost/delegation-result-monitor.sh",
    "delegation-cost/delegation_report.py",
    "usage-report/usage_report.py",
]
WRITE_MULTS = ("1.25", "2.0")


def strip_comments(s):
    return re.sub(r"#[^\n]*", "", s)


def input_prices(text):
    m = re.search(r"PRICE_IN = \[(.*?)\n\]", text, re.S)
    if m:
        return [(k, float(v)) for k, v in ast.literal_eval("[" + strip_comments(m.group(1)) + "]")]
    m = re.search(r"PRICE = \{(.*?)\n\}", text, re.S)
    if m:
        d = ast.literal_eval("{" + strip_comments(m.group(1)) + "}")
        return [(k, float(v[0] if isinstance(v, tuple) else v)) for k, v in d.items()]
    return None


def read_rule(text):
    i = text.find("def read_mult(")
    if i < 0:
        return None
    for line in text[i:].splitlines()[1:]:
        s = line.strip()
        if s.startswith("return "):
            return re.sub(r"\bmodel\b", "m", s[len("return "):]).replace("(model or \"\")", "m")
    return None


fails = 0
ref_file = ref = None
for f in FILES:
    path = os.path.join(root, f)
    try:
        text = open(path).read()
    except OSError:
        print(f"FAIL  {f}: missing"); fails += 1; continue
    prices, rule = input_prices(text), read_rule(text)
    missing = [w for w in WRITE_MULTS if w not in text]
    if prices is None or rule is None:
        print(f"FAIL  {f}: could not find the price table or read_mult"); fails += 1; continue
    if missing:
        print(f"FAIL  {f}: cache-write multiplier(s) {missing} not present"); fails += 1
    if ref is None:
        ref_file, ref = f, (prices, rule)
        print(f"ref   {f}")
        print("      input $/MTok: " + ", ".join(f"{k}={v:g}" for k, v in prices))
        print(f"      cache read:   {rule}")
        continue
    if prices != ref[0]:
        print(f"FAIL  {f}: input prices differ from {ref_file}: {prices}"); fails += 1
    elif rule != ref[1]:
        print(f"FAIL  {f}: cache-read rule differs from {ref_file}: {rule}"); fails += 1
    elif not missing:
        print(f"pass  {f}")
print("----")
print("all price tables identical" if fails == 0 else f"{fails} mismatch(es)")
sys.exit(1 if fails else 0)
PY

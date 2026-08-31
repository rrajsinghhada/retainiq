"""
09_parse_trai.py  (v2 — text-line based)
RetainIQ | Extract Annexure-II and the MNP table from TRAI monthly press releases.

WHY v1 FAILED: TRAI's Annexure-II has no ruling lines, so pdfplumber's default
table detection returns nothing. This version parses extracted TEXT line by
line, anchored on circle names, which is what actually survives their layout.

TWO STRUCTURAL QUIRKS, both discovered by checking against the report's own
arithmetic rather than by assumption:

  1. Operator columns print as (previous, current) pairs, but the TOTAL column
     prints (current, previous) — reversed. Confirmed because
     total[0] - total[1] equals the printed Net Addition on every row.

  2. Column count varies per row. Reliance Com. is effectively defunct (values
     of 0, 1, 2, 51), and MTNL replaces BSNL in Delhi and Mumbai. So operators
     are identified positionally with RCOM filtered out by magnitude:
     Airtel first, Jio last, then Vodafone Idea and BSNL/MTNL in between.

Every row is validated against the Total column before it is emitted. Rows that
fail are reported, never silently dropped.

Usage:
    pip install pdfplumber
    python 09_parse_trai.py --selftest
    python 09_parse_trai.py data/trai/*.pdf --out data/trai_parsed/
"""

import argparse
import csv
import re
import sys
from pathlib import Path

# --- circle vocabulary -------------------------------------------------------

CIRCLES = [
    "Andhra Pradesh", "Assam", "Bihar", "Delhi", "Gujarat", "Haryana",
    "Himachal Pradesh", "J & K", "Karnataka", "Kerala", "Kolkata",
    "Madhya Pradesh", "Maharashtra", "Mumbai", "North East", "Odisha",
    "Punjab", "Rajasthan", "Tamil Nadu", "U.P.(E)", "U.P.(W)", "West Bengal",
]

# Spellings TRAI uses, mapped to our canonical name. Note the MNP table spells
# several circles differently from Annexure-II in the same document.
ALIASES = {
    "andhra pradesh": "Andhra Pradesh", "assam": "Assam", "bihar": "Bihar",
    "delhi": "Delhi", "gujarat": "Gujarat", "gu jarat": "Gujarat",
    "haryana": "Haryana", "himachal pradesh": "Himachal Pradesh", "hp": "Himachal Pradesh",
    "j & k": "J & K", "j&k": "J & K", "jammu & kashmir": "J & K",
    "karnataka": "Karnataka", "kerala": "Kerala", "kolkata": "Kolkata",
    "madhya pradesh": "Madhya Pradesh", "m adhya pradesh": "Madhya Pradesh",
    "maharashtra": "Maharashtra", "m aharashtra": "Maharashtra",
    "mumbai": "Mumbai", "north east": "North East",
    "odisha": "Odisha", "orissa": "Odisha",
    "punjab": "Punjab", "rajasthan": "Rajasthan",
    "tamil nadu": "Tamil Nadu", "chennai": "Tamil Nadu",
    "u.p.(e)": "U.P.(E)", "u.p. (e)": "U.P.(E)", "u.p.(east)": "U.P.(E)",
    "u.p. (east)": "U.P.(E)", "up(e)": "U.P.(E)",
    "u.p.(w)": "U.P.(W)", "u.p. (w)": "U.P.(W)", "u.p.(west)": "U.P.(W)",
    "u.p. (west)": "U.P.(W)", "up(w)": "U.P.(W)",
    "west bengal": "West Bengal", "w est bengal": "West Bengal",
}

# Circles served by MTNL rather than BSNL.
MTNL_CIRCLES = {"Delhi", "Mumbai"}

RCOM_MAX = 10_000          # anything smaller in a middle column is Reliance Com.
MAX_PLAUSIBLE_SUBS = 200_000_000


def norm_circle(raw):
    key = re.sub(r"\s+", " ", raw.strip().lower()).strip(" .:")
    return ALIASES.get(key)



# --- page text ---------------------------------------------------------------

MIN_WIRELESS_CIRCLE_TOTAL = 7_000_000   # separates wireless from wireline rows


def page_text(page):
    """Extract text, un-mirroring rotated annexure pages.

    TRAI renders the annexures in landscape. pdfplumber reads those pages with
    the character order reversed, so "Subscriber Base" arrives as
    "esaB rebircsbuS" and "Annexure-I" as "I-eruxennA". Reversing each line
    restores it, brackets included: ")4(/9/2-PR" -> "RP-2/9/(4)".
    """
    text = page.extract_text() or ""
    if "eruxennA" in text or "rebircsbuS" in text:
        text = "\n".join(line[::-1] for line in text.split("\n"))
    return text


# --- Annexure-II -------------------------------------------------------------

def parse_subscriber_line(line):
    """Parse one Annexure-II row. Returns (circle, {op: subs}) or None.

    Raises ValueError with a specific reason when the row looks like a circle
    row but does not validate, so failures are diagnosable.
    """
    m = re.match(r"^\s*([A-Za-z.&()\s]+?)\s+([\d,]{3}.*)$", line)
    if not m:
        return None
    circle = norm_circle(m.group(1))
    if circle is None:
        return None

    nums = [int(x.replace(",", "")) for x in re.findall(r"-?[\d,]*\d", m.group(2))]
    if len(nums) < 7:
        return None

    # Layout varies between reports, so infer rather than assume:
    #   - some rows carry a trailing Net Addition column, some do not
    #   - the Total pair is (current, previous) in some reports and
    #     (previous, current) in others
    # Try every combination and accept the one the arithmetic supports.
    candidates = []
    for has_net in (True, False):
        body = nums[:-1] if has_net else nums
        net = nums[-1] if has_net else None
        if len(body) % 2 or len(body) < 6:
            continue
        pairs = [(body[i], body[i + 1]) for i in range(0, len(body), 2)]
        total, ops = pairs[-1], pairs[:-1]
        for cur_idx, prev_idx in ((0, 1), (1, 0)):
            cur, prev = total[cur_idx], total[prev_idx]
            if net is not None and cur - prev != net:
                continue
            # operator columns are (previous, current); check both sums
            if sum(o[1] for o in ops) == cur and sum(o[0] for o in ops) == prev:
                # operator pairs read (previous, current) — the header order
                candidates.append((0, ops))
            elif sum(o[0] for o in ops) == cur and sum(o[1] for o in ops) == prev:
                candidates.append((1, [(b, a) for a, b in ops]))
    if not candidates:
        raise ValueError(f"{circle}: {len(nums)} values, no reading of the row "
                         f"reconciles operator columns with the total")
    # Without a Net Addition column both orientations satisfy the sums, so
    # prefer the header convention: (previous, current).
    ops = min(candidates, key=lambda c: c[0])[1]
    circle_total = sum(o[1] for o in ops)

    # Quirk 2: identify operators positionally, filtering out Reliance Com.
    airtel, jio = ops[0], ops[-1]
    middles = [p for p in ops[1:-1] if p[1] >= RCOM_MAX]
    if not middles:
        raise ValueError(f"{circle}: no Vodafone Idea column found")

    out = {"AIRTEL": airtel[1], "JIO": jio[1], "VI": middles[0][1]}
    if len(middles) > 1:
        out["MTNL" if circle in MTNL_CIRCLES else "BSNL"] = middles[1][1]
    return circle, out, circle_total


def parse_annexure_ii(pdf, report_month, source_file, errors):
    """Parse every line in the document and keep the rows that hold up.

    No attempt is made to locate the annexure page: body text elsewhere
    mentions "Annexure-II" and the rotated pages do not contain the string at
    all. Instead each line is parsed, and a row is accepted only if its
    operator columns reconcile against its own total AND that total is
    wireless-sized. Wireline circle totals run under 6 million against 8
    million-plus for wireless, so magnitude separates the two annexures.
    """
    best = {}
    for page in pdf.pages:
        for line in page_text(page).split("\n"):
            try:
                parsed = parse_subscriber_line(line)
            except ValueError:
                continue          # wrong table; only report if nothing is found
            if not parsed:
                continue
            circle, ops, total = parsed
            if total < MIN_WIRELESS_CIRCLE_TOTAL:
                continue          # wireline annexure
            if circle not in best or total > best[circle][1]:
                best[circle] = (ops, total)

    rows = []
    for circle, (ops, _) in best.items():
        for code, subs in ops.items():
            rows.append(dict(source_file=source_file, report_month=report_month,
                             circle_raw=circle, operator_raw=code,
                             subscribers=subs))
    if not rows:
        errors.append("no wireless subscriber rows reconciled on any page")
    return rows


# --- MNP ---------------------------------------------------------------------

def parse_mnp(pdf, report_month, source_file, errors):
    """Cumulative porting requests per circle.

    Circle names wrap across lines in this table ("Andhra" / "Pradesh"), so the
    whole page is collapsed to one whitespace-normalised string and each circle
    is located by name followed by two decimals.
    """
    rows, seen = [], set()
    for page in pdf.pages:
        text = page_text(page)
        if "MNP" not in text.upper():
            continue
        flat = re.sub(r"\s+", " ", text)
        # longest names first so "Andhra Pradesh" wins over a bare match
        for alias in sorted(ALIASES, key=len, reverse=True):
            circle = ALIASES[alias]
            if circle in seen:
                continue
            # Two-word circle names wrap inside the cell, which can push the
            # second word past the numbers ("Andhra 74.62 75.31 Pradesh").
            # Make every word after the first optional.
            words = alias.split()
            pattern = re.escape(words[0]) + "".join(
                r"(?:\s+" + re.escape(w) + ")?" for w in words[1:])
            m = re.search(pattern + r"\s+(\d+\.\d+)\s+(\d+\.\d+)", flat, re.I)
            if not m:
                continue
            prev, curr = float(m.group(1)), float(m.group(2))
            if curr < prev:
                errors.append(f"{circle}: cumulative ports fell "
                              f"{prev} -> {curr}, which is impossible")
                continue
            seen.add(circle)
            rows.append(dict(source_file=source_file, report_month=report_month,
                             zone_raw="", circle_raw=circle,
                             cumulative_ports=curr))
    return rows


# --- validation --------------------------------------------------------------

def validate(sub_rows, mnp_rows, source_file, errors):
    problems = list(errors)

    warnings = []
    found = {r["circle_raw"] for r in sub_rows}
    missing = set(CIRCLES) - found
    if len(missing) > 2:
        problems.append(f"Annexure-II missing circles: {sorted(missing)}")
    elif missing:
        warnings.append(f"Annexure-II missing {sorted(missing)} "
                        f"-- emitted anyway, note the gap")
    if not any(r["operator_raw"] == "VI" for r in sub_rows):
        problems.append("no Vodafone Idea rows -- column mapping wrong")
    for r in sub_rows:
        if not (0 <= r["subscribers"] <= MAX_PLAUSIBLE_SUBS):
            problems.append(f"implausible count: {r}")

    mnp_missing = set(CIRCLES) - {r["circle_raw"] for r in mnp_rows}
    if mnp_rows and len(mnp_missing) > 2:
        problems.append(f"MNP missing circles: {sorted(mnp_missing)}")
    elif mnp_rows and mnp_missing:
        warnings.append(f"MNP missing {sorted(mnp_missing)}")

    if problems:
        print(f"  FAIL {source_file}", file=sys.stderr)
        for p in problems[:10]:
            print(f"    - {p}", file=sys.stderr)
        return False
    for w in warnings:
        print(f"  warn {source_file}: {w}")
    vi = next((r["subscribers"] for r in sub_rows
               if r["operator_raw"] == "VI" and r["circle_raw"] == "Rajasthan"), 0)
    print(f"  ok   {source_file}: {len(sub_rows)} subscriber rows, "
          f"{len(mnp_rows)} MNP rows (Vi Rajasthan: {vi:,})")
    return True


# --- self-test ---------------------------------------------------------------

SAMPLES = [
    ("Andhra Pradesh 34,242,244 34,321,932 0 0 9,596,019 9,503,297 6,914,850 "
     "6,916,286 31,919,256 31,730,391 82,471,906 82,672,369 -200463",
     "Andhra Pradesh", {"AIRTEL": 34321932, "VI": 9503297, "BSNL": 6916286,
                        "JIO": 31730391}),
    ("Delhi 19,006,627 19,071,921 1 2 16,728,046 16,650,505 174,758 174,277 "
     "19,893,256 20,027,060 55,923,765 55,802,688 121077",
     "Delhi", {"AIRTEL": 19071921, "VI": 16650505, "MTNL": 174277,
               "JIO": 20027060}),
    ("Rajasthan 23,414,504 23,418,747 51 50 8,984,641 8,886,044 5,617,556 "
     "5,624,794 26,815,995 26,733,882 64,663,517 64,832,747 -169230",
     "Rajasthan", {"AIRTEL": 23418747, "VI": 8886044, "BSNL": 5624794,
                   "JIO": 26733882}),
    ("Assam 12,307,089 12,351,382 1,429,694 1,442,516 2,949,537 2,925,869 "
     "9,755,628 9,749,921 26,469,688 26,441,948 27740",
     "Assam", {"AIRTEL": 12351382, "VI": 1442516, "BSNL": 2925869,
               "JIO": 9749921}),
    # 2026-05 style: Total pair printed (previous, current) — reversed
    ("Rajasthan 23,414,504 23,418,747 51 50 8,984,641 8,886,044 5,617,556 "
     "5,624,794 26,815,995 26,733,882 64,832,747 64,663,517 -169230",
     "Rajasthan", {"AIRTEL": 23418747, "VI": 8886044, "BSNL": 5624794,
                   "JIO": 26733882}),
    # 2026-07 style: no trailing Net Addition column
    ("Assam 12,307,089 12,351,382 1,429,694 1,442,516 2,949,537 2,925,869 "
     "9,755,628 9,749,921 26,441,948 26,469,688",
     "Assam", {"AIRTEL": 12351382, "VI": 1442516, "BSNL": 2925869,
               "JIO": 9749921}),
]


def selftest():
    ok = True
    for line, want_circle, want_ops in SAMPLES:
        got_circle, got_ops, _ = parse_subscriber_line(line)
        if got_circle != want_circle or got_ops != want_ops:
            print(f"FAIL {want_circle}\n  expected {want_ops}\n  got      {got_ops}")
            ok = False
        else:
            print(f"pass {want_circle}: Vi = {got_ops['VI']:,}")
    print("\nself-test passed" if ok else "\nSELF-TEST FAILED")
    return 0 if ok else 1


# --- main --------------------------------------------------------------------

def month_from_filename(path):
    m = re.search(r"(\d{4})[_-](\d{2})", Path(path).stem)
    if not m:
        raise ValueError(f"cannot read month from {path}; use trai_YYYY_MM.pdf")
    return f"{m.group(1)}-{m.group(2)}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pdfs", nargs="*")
    ap.add_argument("--out", default="data/trai_parsed")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        sys.exit(selftest())
    if not args.pdfs:
        ap.error("give some PDFs, or --selftest")

    import pdfplumber

    outdir = Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)
    all_sub, all_mnp, failed = [], [], []

    for path in args.pdfs:
        source_file = Path(path).name
        month = month_from_filename(path)
        errors = []
        with pdfplumber.open(path) as pdf:
            sub_rows = parse_annexure_ii(pdf, month, source_file, errors)
            mnp_rows = parse_mnp(pdf, month, source_file, errors)
        if validate(sub_rows, mnp_rows, source_file, errors):
            all_sub.extend(sub_rows)
            all_mnp.extend(mnp_rows)
        else:
            failed.append(source_file)

    with open(outdir / "trai_operator_circle.csv", "w", newline="") as f:
        w = csv.DictWriter(f, ["source_file", "report_month", "circle_raw",
                               "operator_raw", "subscribers"])
        w.writeheader(); w.writerows(all_sub)

    with open(outdir / "trai_mnp.csv", "w", newline="") as f:
        w = csv.DictWriter(f, ["source_file", "report_month", "zone_raw",
                               "circle_raw", "cumulative_ports"])
        w.writeheader(); w.writerows(all_mnp)

    print(f"\nparsed {len(args.pdfs) - len(failed)}/{len(args.pdfs)} files")
    print(f"{len(all_sub)} subscriber rows, {len(all_mnp)} MNP rows")
    if failed:
        print(f"FAILED: {failed}")
        sys.exit(1)


if __name__ == "__main__":
    main()

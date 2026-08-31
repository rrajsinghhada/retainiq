# Recommendation and experiment design

*Drop-in replacement for the recommendation section of README.md, and a new
section for DIAGNOSIS.md before "What this analysis cannot tell us".*

---

## What RetainIQ recommends

The project answers four questions, and the fourth is the one worth having.

**1. Who should we contact?** The 4,256 subscribers whose value at risk exceeds
₹370, ranked by value at risk. Ranking is driven by predicted churn probability
multiplied by lifetime value, so it does not collapse into "whoever is most
likely to leave".

**2. What is the best campaign we can run today?** A uniform ₹160 offer to that
population. Modelled net contribution ₹1,275,282. The optimum is flat between
₹140 and ₹160 — net contribution varies by 0.01% across that range — so the
recommendation survives a material error in the response assumptions.

**3. Could personalised offer sizing do better?** Potentially, and substantially.
Sizing each offer from the first-order condition `c* = k·ln(VaR·S/k)` produces a
four-band campaign (₹250 / ₹200 / ₹150 / ₹100) worth ₹1,314,266 — a 3.1%
improvement under the central response curve.

**4. Should we deploy personalisation now? No.** Re-running the same optimiser
under alternative response curves moves the outcome from **+66% to −77%**
against the uniform campaign. The downside exceeds the upside, and there is no
evidence identifying which curve is real, because all three were assumed. A
strategy whose sign depends on an unmeasured parameter is not ready for
production.

| Response curve | Customers | Spend | Net contribution | vs uniform |
|---|---|---|---|---|
| Uniform ₹160 | 4,256 | ₹680,960 | ₹1,275,282 | — |
| Personalised, central | 4,607 | ₹647,250 | ₹1,314,266 | +3.06% |
| Personalised, steep | 5,126 | ₹540,800 | ₹2,120,176 | +66.25% |
| Personalised, flat | 2,992 | ₹470,100 | ₹287,780 | −77.43% |

The recommendation is therefore the simpler strategy, held until experimental
evidence licenses the sophisticated one.

## The experiment that would license personalisation

A single-offer campaign cannot estimate a response curve. Sending everyone ₹160
measures the response to ₹160 and nothing else; the shape between ₹80 and ₹320
stays unknown, which is precisely the shape the optimiser depends on. Measuring
it requires randomised assignment across multiple offer levels.

**Design.** Randomise the target population across a zero-offer control and
three or four offer levels, stratified by value band.

| Arm | Offer | Purpose |
|---|---|---|
| Control | ₹0 | Establishes the counterfactual retention rate |
| A | ₹100 | Lower region of the curve |
| B | ₹200 | Near the modelled optimum |
| C | ₹320 | Upper region, where returns should flatten |

**Why four arms and not six.** With 4,256 subscribers, a six-arm split leaves
about 709 per cell, which at 80% power detects a difference of roughly 7.3
percentage points in retention. Adjacent offer levels will differ by far less
than that, so a six-arm test would resolve nothing between neighbouring points.
Four arms give about 1,064 per cell and detect around 6.0 points.

| Arms | Subscribers per arm | Minimum detectable difference |
|---|---|---|
| 2 | 2,128 | 4.3 pp |
| 3 | 1,419 | 5.2 pp |
| 4 | 1,064 | 6.0 pp |
| 6 | 709 | 7.3 pp |

**Analyse by fitting, not by comparing.** The question is not whether ₹200 beats
₹100 pairwise. It is the value of *S* and *k* in `s(c) = S(1 − e^(−c/k))`, and
those two parameters are estimated across all arms simultaneously. Fitting a
two-parameter curve needs three offer levels plus a control, not six, and pools
the data far more efficiently than adjacent contrasts.

**Stratify the randomisation.** At roughly 1,000 per cell, simple randomisation
can allocate a disproportionate share of high-value subscribers to one arm, and
the resulting difference would be misread as an offer effect. Randomise within
each of the four value bands.

**The control arm has a price, and it should be stated.** Withholding offers
from ~1,000 at-risk subscribers with a mean value at risk of ₹1,033 forgoes
roughly ₹446,000 of expected saved contribution over the campaign. That is the
cost of knowing. Set against a personalisation decision whose range is +66% to
−77% on a ₹1.28M base, it is worth paying.

**What it unlocks.** With *S* and *k* measured rather than assumed, the same
optimiser re-runs on evidence: `decision.response_curve` takes the fitted
parameters, `v_tiered_offers` recalculates, and the personalisation decision
becomes defensible. The experiment also yields the incremental save rate
directly, which is the parameter the entire economics layer rests on and the
one thing observational data can never supply.

---

## Three lines for the README summary

> Customer-level offer sizing increased expected contribution by 3.1% under the
> central response curve, but sensitivity testing ranged from +66% to −77%.
>
> Because personalised optimisation depends heavily on an unmeasured
> offer-response curve, the recommended production strategy remains the robust
> ₹160 uniform offer.
>
> Next step: run a randomised multi-offer holdout experiment to estimate
> incremental response by offer size, then re-optimise customer-level retention
> spend using measured uplift.

## Naming

Call the file and the views what they are. The finding is not "use tiers" — it
is "the data does not yet justify tiers".

- `10_tiered_offers.sql` → **Personalised Offer Sensitivity Analysis**
- `decision.v_tiered_offers` → keep the view name, describe it as the
  personalisation optimiser rather than the recommendation
- `decision.v_tiered_vs_uniform` → the headline artefact, since the comparison
  is the result

## Resume bullets

Lead with the robust decision, not the more complicated model.

- Optimised retention spend across 20 offer scenarios, identifying a ₹160
  strategy for 4,256 subscribers with ₹1.28M modelled net contribution.
- Stress-tested personalised offer sizing across response assumptions,
  revealing a +66% to −77% outcome range and specifying the randomised
  experiment required before deployment.

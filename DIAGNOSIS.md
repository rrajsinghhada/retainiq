# Retention Diagnosis

**RetainIQ | Subscriber base: 7,043 | Prepared by Rishiraj Singh Hada**

---

## What is happening

We are losing 26.5% of the subscriber base, and those leavers carry 30.5% of
monthly revenue — ₹139,131 of ₹456,117. Churn is not spread evenly across the
book: 61.6% of the lost revenue comes from subscribers billing ₹80 a month or
more, who churn at 34.0% against 22.0% for everyone else.

The concentration is not a simple straight line, and it is worth being precise
about the shape. Sorted into value deciles, churn climbs to 40.9% in the ninth
decile and then falls back to 24.7% in the tenth. Our very highest spenders are
not our biggest flight risk. The damage sits in the upper-middle of the value
distribution — subscribers paying ₹70 to ₹103 — which is where volume and churn
rate overlap.

One pattern explains almost all of it, and it is not the obvious one.

**Commitment, not tenure, is what protects us.** Churn on month-to-month plans
is 42.7%. On one-year contracts it is 11.3%. On two-year contracts it is 2.8% —
a fifteen-fold spread, on a base with almost identical average revenue across
the three tiers. The model puts the same finding in odds terms: a two-year
contract carries 0.19x the churn odds of month-to-month, the largest coefficient
in the model.

**The apparent tenure effect is mostly contract mix.** In aggregate, churn looks
like a lifecycle problem: 52.9% in the first six months falling to 9.5% past
four years. But that pattern does not survive controlling for contract type.
Within month-to-month it holds strongly, falling from 55.2% to 26.0%. Within
one-year contracts churn actually *rises* with tenure, from 10.3% to 12.9%, and
within two-year contracts from 0% to 3.3%. The aggregate curve is driven by
composition — 1,263 of the 2,239 subscribers past four years sit on two-year
contracts.

The correct statement is therefore narrower and more useful: surviving the first
six months does not make a subscriber safe. Being on a committed contract does.
Early tenure matters because that is when month-to-month subscribers leave, not
because month seven is inherently safer than month five.

What does hold across every contract tier is that revenue rises with tenure —
from ₹55.88 to ₹85.45 within month-to-month alone. Customers who stay become
more valuable regardless of what they signed.

## Why it is happening

**The premium product performs worst.** Fibre optic subscribers churn at 41.9%
against 19.0% on DSL, and they are our highest-revenue segment at ₹91.50 a month.
This is the most important finding in the diagnosis, because it inverts the
intuition that better product means better retention. The pattern is consistent
with a price-to-expectation gap: fibre customers pay 57% more than DSL customers
and leave at more than twice the rate. Either the service is not delivering
against what the price implies, or competitor offers are landing hardest exactly
where our bills are highest. Distinguishing between those two requires
complaint-level data we do not have.

**Payment method is a commitment proxy.** Electronic check users churn at 45.3%
against 15-19% for every other method. There is nothing about the payment rail
itself that would cause this. What it marks is the absence of a stored payment
instrument — no card on file, no automatic renewal, no friction on the way out.
Each billing cycle is a fresh decision rather than a default.

**Product attachment protects, but only past the first add-on.** Subscribers
with five or six services attached churn at 12.4% and 5.3%. Those with exactly
one churn at 45.8% — worse than those with none, which is a compositional
artefact, since the zero-attachment group is largely phone-only customers paying
₹32.79 who have little to leave. The usable finding is the gradient from one
service upward: each additional attached service is associated with materially
lower churn, and the customers carrying five or six are our most profitable at
₹92-99 a month.

**These factors compound.** Subscribers who are simultaneously month-to-month,
on fibre, and paying by electronic check churn at 60.4%. That is 1,307
subscribers — 18.6% of the base — behaving like a distinct high-risk segment
rather than three independent risk factors.

## What we should do about it

A churn model alone does not produce a decision. Knowing that 1,869 subscribers
are likely to leave says nothing about which of them are worth paying to keep.
The value layer answers that: each subscriber's lifetime value is multiplied by
their predicted churn probability to give a value at risk, and an offer is worth
making only when the expected saved contribution exceeds its cost.

**Recommendation: a ₹160 retention offer, extended to the 4,256 subscribers
whose value at risk exceeds ₹370.**

That is 60.4% of the base, and it produces a net contribution of ₹1,275,282.
Scenario testing across offer sizes from ₹20 to ₹400 shows the return peaking in
the ₹140-160 range and falling away sharply on either side. At ₹400 per
subscriber the programme returns ₹718,147 — 44% less — because the threshold
rises faster than the persuasion improves. Spending more per head is not
spending better.

The recommendation is robust: net contribution varies by 0.01% between ₹140 and
₹160, so a material error in the response assumptions still lands close to the
best achievable outcome.

**Where the offer should be aimed.** The value ranking is the operational
output, but three structural interventions follow directly from the diagnosis
and are likely to outperform discounting:

1. **Contract migration.** Moving month-to-month subscribers to annual terms is
   associated with the largest churn reduction in the data. This is a
   proposition problem, not a discount problem.
2. **Payment instrument capture.** Converting electronic-check payers to stored
   automatic methods removes a recurring exit decision.
3. **Early intervention on uncommitted subscribers specifically.** Month-to-month
   subscribers in their first six months churn at 55.2%. This is where the
   lifecycle and commitment findings intersect, and it is the single most
   addressable group in the base. Note the corollary: a long-tenured
   month-to-month subscriber still churns at 26.0%, so tenure alone is not a
   reason to deprioritise someone.

## What this analysis cannot tell us

Three limits, stated plainly.

**We are measuring propensity, not persuadability.** The model identifies who is
likely to leave. It does not identify who can be talked out of it, and these are
different populations — a subscriber with a 90% churn probability may be
unreachable while one at 50% is highly persuadable. Resolving this requires an
uplift model trained on a randomised holdout, where the offer is withheld from a
random control group and the difference measured. No amount of observational
data substitutes for that experiment.

**The response curve is assumed, not measured.** The relationship between offer
size and save rate is asserted from judgment. Sensitivity scenarios spanning a
25% to 55% save rate are included; the recommendation holds across that range,
but the underlying curve is an input, not a finding.

**Contract effects are correlational.** Two-year contracts are associated with
2.8% churn. Whether the contract causes the retention, or whether customers who
were already committed are the ones who sign long contracts, cannot be separated
from this data. The migration recommendation above should be piloted and
measured, not assumed.

---

*Subscriber-level data: IBM Telco Customer Churn sample (7,043 subscribers).
Model: logistic regression, AUC 0.841, 76.1% precision and 2.87x lift in the top
decile, 25% holdout. All figures reproducible from the project warehouse.*

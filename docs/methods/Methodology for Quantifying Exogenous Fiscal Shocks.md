To replicate the quarterly dataset used by Romer and Romer to analyze fiscal shocks, follow this comprehensive instruction set for processing original sources and quantifying liability changes.

**Terminology note:** R&R's original paper uses "Phase" for these methodology steps. To avoid collision with the project's Phase 0-3 development stages, we label these RR1-RR6 throughout project documentation.

### RR1: Source Material Compilation

1. **Gather contemporaneous executive records**, specifically the *Economic Report of the President*, the *Annual Report of the Secretary of the Treasury*, and the *Budget of the United States Government* 1, 2\.  
2. **Collect primary legislative documents**, including reports from the **House Ways and Means Committee** and the **Senate Finance Committee**, as well as the *Congressional Record* for floor debates 3, 4\.  
3. **Incorporate technical and non-partisan analysis** from the **Congressional Budget Office (CBO)** for post-1974 measures and **Conference reports** for final bill versions 3, 5\.  
4. **Use specialized sources for Social Security taxes**, such as the *Social Security Bulletin* and annual reports from the Social Security trust fund trustees 6, 7\.

### RR2: Identifying and Filtering Measures

1. **Apply the "Significant Mention" rule**: Analyze only those tax actions that receive more than an incidental or passing reference in the primary sources 6, 8\.
2. **Verify actual liability changes**: Exclude laws that merely **extend existing expiring taxes** or administrative actions that only alter **withholding timing** without changing the total amount owed by taxpayers 9, 10\.
3. **Include diverse tax types**: Ensure the dataset captures changes across personal and corporate income taxes, payroll taxes, and excise taxes 9, 10\.
4. **Include executive actions**: A few significant actions are not legislation but executive orders changing depreciation guidelines substantially (e.g., 1962 depreciation guideline changes). These are included if they meet the significant mention rule.

**Total count**: R&R identify **50 significant federal tax actions** in the postwar era (1945-2007). Many involve phased implementation leading to revenue changes across multiple quarters.

### RR3: Quantification of Size

1. **Extract real-time revenue estimates**: Use the **nominal revenue effect** that policymakers *expected* the law to have at the time it was enacted 11, 12\.  
2. **Prioritize "Consensus" figures**: Use straightforward statements of expected revenue found in the *Economic Reports* 11, 13\.  
3. **Use a fallback hierarchy for missing data**: If implementation-quarter estimates are unavailable, use estimates for the **first full calendar year**; if those are also missing, use the **first full fiscal year** 11, 14\.  
4. **Isolate policy-driven changes**: If revenue projections rise over time solely due to **economic growth** rather than law changes, exclude the growth-driven portion of the revenue estimate 15\.  
5. **Calculate Present Value (Alternative Series)**: To account for permanent income hypothesis effects, discount the stream of all future tax changes in a bill back to the **quarter of passage** using the **three-year Treasury bond rate** 16, 17\.

### RR4: Determining Timing and Quarter Assignment

* **Assign to implementation date**: Date the shock to the quarter in which **tax liabilities actually changed**, rather than the date of legislation 18, 19\.  
* **Apply the "Midpoint" rule**: If a tax change takes effect **before the midpoint of a quarter**, assign it to that quarter; if after the midpoint, assign it to the following quarter 11, 20\.  
* **Account for Phased Changes**: If a law implements changes in steps, record each step as a separate **sequence of revenue effects** in their respective implementation quarters 11, 15\.  
* **Handle Retroactivity (Standard vs. Adjusted)**:
  * **Standard Series**: In the baseline version, ignore retroactive features to simplify analysis 20, 21\.
  * **Adjusted Series**: Treat a retroactive component as a **one-time levy or rebate** 21, 22\. Calculate the one-time effect (the annual rate multiplied by the number of retroactive quarters) and record it as a surge in the implementation quarter, followed by a corresponding drop the next quarter to return to the steady state 23\.
  * **Retroactive calculation example**: The Excess Profits Tax Act of 1950 imposed a tax retroactive to July 1950, signed January 1951. Ongoing effect: $3.5B annual rate starting 1951Q1. Retroactive component covers 2 quarters, so the one-time levy is $7B at annual rate. Combined 1951Q1: $10.5B; 1951Q2 change: -$7B (returning to steady-state $3.5B).

### RR5: Motivation Classification (Exogeneity Filter)

* **Discard Endogenous Changes**: Exclude tax changes taken in response to **prospective economic conditions** or **spending-driven** reasons (e.g., paying for a war) as they are correlated with other factors affecting output 24-27.
* **Identify Exogenous Fiscal Shocks**: Include only measures motivated by factors unrelated to current or prospective short-run growth:
  * **Deficit-driven**: Changes aimed at reducing an inherited budget deficit resulting from past decisions 28, 29\.
  * **Long-run goals**: Changes motivated by philosophical beliefs in smaller government, fairness, or raising the **long-run growth rate of potential output** 30-32.

**Edge cases and boundary rules:**

* **Countercyclical vs. Long-run**: The key distinction is whether the goal is to "return growth to normal" (countercyclical) or "raise growth above normal" (long-run). If policymakers predict unemployment will rise, the action is countercyclical. If they say growth is normal but want it faster, it is long-run.
* **Spending-driven vs. Deficit-driven**: A tax increase to pay for higher spending is spending-driven if within 1 year of the spending increase; deficit-driven if more than 1 year after. This rule matters for Social Security amendments where tax rate increases were phased years after benefit increases.
* **Mixed motivations**: Most acts have a single dominant motivation cited consistently across sources. When sources disagree, use the most frequently cited motivation. When motivation changes during deliberations, use the prevailing motivation at time of passage. When genuinely mixed (e.g., EGTRRA 2001), apportion revenue effects among motivations: the 2001 rebate component is countercyclical, while 2002+ rate reductions are long-run.
* **Offsetting exogenous changes**: When a countercyclical tax cut offsets a previous exogenous tax increase, classify the offset with the same motivation as the original change (not countercyclical), to avoid recording two opposite-motivation changes in a quarter where liabilities did not change.
* **Conflicting sources**: When executive and legislative documents disagree on motivation, use the most frequently cited reason across all sources.

### RR6: Final Scaling and Dataset Aggregation

1. **Normalize by GDP**: Express each quarterly nominal shock as a **percentage of nominal GDP** in the quarter the change was assigned 33, 34\.  
2. **Aggregate multiple actions**: If more than one law of the same motivation category takes effect in a single quarter, **sum their GDP percentages** into a single entry 35\.  
3. **Finalize the series**: The result is a quarterly time series (starting in 1947\) where most observations are zero, punctuated by discrete entries for **exogenous fiscal shocks** 33, 36, 37\.


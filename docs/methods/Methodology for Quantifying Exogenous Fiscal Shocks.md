To replicate the quarterly dataset used by Romer and Romer to analyze fiscal shocks, follow this comprehensive instruction set for processing original sources and quantifying liability changes.

### Phase 1: Source Material Compilation

1. **Gather contemporaneous executive records**, specifically the *Economic Report of the President*, the *Annual Report of the Secretary of the Treasury*, and the *Budget of the United States Government* 1, 2\.  
2. **Collect primary legislative documents**, including reports from the **House Ways and Means Committee** and the **Senate Finance Committee**, as well as the *Congressional Record* for floor debates 3, 4\.  
3. **Incorporate technical and non-partisan analysis** from the **Congressional Budget Office (CBO)** for post-1974 measures and **Conference reports** for final bill versions 3, 5\.  
4. **Use specialized sources for Social Security taxes**, such as the *Social Security Bulletin* and annual reports from the Social Security trust fund trustees 6, 7\.

### Phase 2: Identifying and Filtering Measures

1. **Apply the "Significant Mention" rule**: Analyze only those tax actions that receive more than an incidental or passing reference in the primary sources 6, 8\.  
2. **Verify actual liability changes**: Exclude laws that merely **extend existing expiring taxes** or administrative actions that only alter **withholding timing** without changing the total amount owed by taxpayers 9, 10\.  
3. **Include diverse tax types**: Ensure the dataset captures changes across personal and corporate income taxes, payroll taxes, and excise taxes 9, 10\.

### Phase 3: Quantification of Size

1. **Extract real-time revenue estimates**: Use the **nominal revenue effect** that policymakers *expected* the law to have at the time it was enacted 11, 12\.  
2. **Prioritize "Consensus" figures**: Use straightforward statements of expected revenue found in the *Economic Reports* 11, 13\.  
3. **Use a fallback hierarchy for missing data**: If implementation-quarter estimates are unavailable, use estimates for the **first full calendar year**; if those are also missing, use the **first full fiscal year** 11, 14\.  
4. **Isolate policy-driven changes**: If revenue projections rise over time solely due to **economic growth** rather than law changes, exclude the growth-driven portion of the revenue estimate 15\.  
5. **Calculate Present Value (Alternative Series)**: To account for permanent income hypothesis effects, discount the stream of all future tax changes in a bill back to the **quarter of passage** using the **three-year Treasury bond rate** 16, 17\.

### Phase 4: Determining Timing and Quarter Assignment

* **Assign to implementation date**: Date the shock to the quarter in which **tax liabilities actually changed**, rather than the date of legislation 18, 19\.  
* **Apply the "Midpoint" rule**: If a tax change takes effect **before the midpoint of a quarter**, assign it to that quarter; if after the midpoint, assign it to the following quarter 11, 20\.  
* **Account for Phased Changes**: If a law implements changes in steps, record each step as a separate **sequence of revenue effects** in their respective implementation quarters 11, 15\.  
* **Handle Retroactivity (Standard vs. Adjusted)**:  
* **Standard Series**: In the baseline version, ignore retroactive features to simplify analysis 20, 21\.  
* **Adjusted Series**: Treat a retroactive component as a **one-time levy or rebate** 21, 22\. Calculate the one-time effect (the annual rate multiplied by the number of retroactive quarters) and record it as a surge in the implementation quarter, followed by a corresponding drop the next quarter to return to the steady state 23\.

### Phase 5: Motivation Classification (Exogeneity Filter)

* **Discard Endogenous Changes**: Exclude tax changes taken in response to **prospective economic conditions** or **spending-driven** reasons (e.g., paying for a war) as they are correlated with other factors affecting output 24-27.  
* **Identify Exogenous Fiscal Shocks**: Include only measures motivated by factors unrelated to current or prospective short-run growth:  
* **Deficit-driven**: Changes aimed at reducing an inherited budget deficit resulting from past decisions 28, 29\.  
* **Long-run goals**: Changes motivated by philosophical beliefs in smaller government, fairness, or raising the **long-run growth rate of potential output** 30-32.

### Phase 6: Final Scaling and Dataset Aggregation

1. **Normalize by GDP**: Express each quarterly nominal shock as a **percentage of nominal GDP** in the quarter the change was assigned 33, 34\.  
2. **Aggregate multiple actions**: If more than one law of the same motivation category takes effect in a single quarter, **sum their GDP percentages** into a single entry 35\.  
3. **Finalize the series**: The result is a quarterly time series (starting in 1947\) where most observations are zero, punctuated by discrete entries for **exogenous fiscal shocks** 33, 36, 37\.

